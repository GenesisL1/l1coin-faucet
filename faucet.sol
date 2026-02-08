/*
MIT License

Copyright (c) 2026 GenesisL1
Copyright (c) 2026 L1 Coin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * GenesisL1 Faucet — BROWSER-ONLY anti-bot:
 * - 11 L1 per address (one-time)
 * - On-chain quiz (question text + 4 options)
 * - UI checks answers via eth_call (checkAnswer)
 * - On-chain PoW "captcha" (browser mines nonce, contract verifies)
 */
contract GenesisL1FaucetQuizPoW {
    // ------------------ ownership ------------------
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "NOT_OWNER"); _; }

    // ------------------ faucet config ------------------
    bool public paused;
    uint256 public claimAmountWei = 11 ether;

    // PoW: require keccak256(challenge || powNonce) <= (2^(256-diff)-1)
    uint8  public powDifficultyBits = 20;     // tune
    uint8  public maxChallengeAgeBlocks = 64; // tune (still bounded by EVM 256-block blockhash window)

    mapping(address => bool) public hasClaimed;
    mapping(address => uint256) public userSalt; // changes challenge per user if ever needed

    // ------------------ reentrancy guard ------------------
    uint256 private _lock = 1;
    modifier nonReentrant() {
        require(_lock == 1, "REENTRANCY");
        _lock = 2;
        _;
        _lock = 1;
    }

    // ------------------ quiz storage (no string[4] calldata/returns) ------------------
    struct Question {
        string text;
        string o0;
        string o1;
        string o2;
        string o3;
        bytes32 correctHash; // keccak256(bytes(option[correctIndex]))
    }
    Question[] private _questions;

    // ------------------ events ------------------
    event Funded(address indexed from, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event Paused(bool paused);
    event ClaimAmountUpdated(uint256 amountWei);
    event PowUpdated(uint8 difficultyBits, uint8 maxAgeBlocks);
    event QuestionAdded(uint256 indexed id);
    event QuestionUpdated(uint256 indexed id);
    event OwnerChanged(address indexed newOwner);

    constructor() payable {
        owner = msg.sender;
        emit OwnerChanged(owner);

        // Example questions — replace with your GenesisL1 facts
        _addQuestion(
            "GenesisL1 is compatible with which VM?",
            "EVM", "JVM", "WASM-only", "None",
            0
        );
        _addQuestion(
            "GenesisL1 reference deployment chain-id is:",
            "29", "1", "8453", "137",
            0
        );
        _addQuestion(
            "GenesisL1 is built on which stack?",
            "Cosmos SDK / Ethermint", "Solana", "Bitcoin Core", "Substrate",
            0
        );

        if (msg.value > 0) emit Funded(msg.sender, msg.value);
    }

    // ------------------ funding ------------------
    receive() external payable { emit Funded(msg.sender, msg.value); }
    function fund() external payable { emit Funded(msg.sender, msg.value); }

    function faucetBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdraw(uint256 amountWei, address payable to) external onlyOwner {
        require(to != address(0), "BAD_TO");
        require(amountWei <= address(this).balance, "INSUFFICIENT");
        (bool ok,) = to.call{value: amountWei}("");
        require(ok, "WITHDRAW_FAIL");
    }

    // ------------------ admin controls ------------------
    function setPaused(bool v) external onlyOwner {
        paused = v;
        emit Paused(v);
    }

    function setClaimAmountWei(uint256 v) external onlyOwner {
        claimAmountWei = v;
        emit ClaimAmountUpdated(v);
    }

    function setPow(uint8 difficultyBits, uint8 maxAgeBlocks) external onlyOwner {
        require(difficultyBits > 0 && difficultyBits <= 32, "DIFF_RANGE");
        require(maxAgeBlocks >= 3 && maxAgeBlocks <= 128, "AGE_RANGE");
        powDifficultyBits = difficultyBits;
        maxChallengeAgeBlocks = maxAgeBlocks;
        emit PowUpdated(difficultyBits, maxAgeBlocks);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BAD_OWNER");
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    // ------------------ quiz: view ------------------
    function questionCount() external view returns (uint256) {
        return _questions.length;
    }

    function getQuestion(uint256 id)
        external
        view
        returns (string memory text, string memory o0, string memory o1, string memory o2, string memory o3)
    {
        require(id < _questions.length, "BAD_ID");
        Question storage q = _questions[id];
        return (q.text, q.o0, q.o1, q.o2, q.o3);
    }

    function checkAnswer(uint256 id, uint8 selected) external view returns (bool) {
        if (id >= _questions.length) return false;
        if (selected > 3) return false;
        Question storage q = _questions[id];
        return _selectedHash(q, selected) == q.correctHash;
    }

    function validateAll(uint8[] calldata answers) external view returns (bool) {
        if (answers.length != _questions.length) return false;
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i] > 3) return false;
            if (_selectedHash(_questions[i], answers[i]) != _questions[i].correctHash) return false;
        }
        return true;
    }

    // ------------------ quiz: admin ------------------
    function addQuestion(
        string calldata text,
        string calldata o0,
        string calldata o1,
        string calldata o2,
        string calldata o3,
        uint8 correctIndex
    ) external onlyOwner {
        _addQuestion(text, o0, o1, o2, o3, correctIndex);
    }

    function setQuestion(
        uint256 id,
        string calldata text,
        string calldata o0,
        string calldata o1,
        string calldata o2,
        string calldata o3,
        uint8 correctIndex
    ) external onlyOwner {
        require(id < _questions.length, "BAD_ID");
        require(correctIndex < 4, "BAD_CORRECT");

        Question storage q = _questions[id];
        q.text = text;
        q.o0 = o0;
        q.o1 = o1;
        q.o2 = o2;
        q.o3 = o3;
        q.correctHash = _optionHashByIndex(q, correctIndex);

        emit QuestionUpdated(id);
    }

    function _addQuestion(
        string memory text,
        string memory o0,
        string memory o1,
        string memory o2,
        string memory o3,
        uint8 correctIndex
    ) internal {
        require(correctIndex < 4, "BAD_CORRECT");
        Question storage q = _questions.push();
        q.text = text;
        q.o0 = o0;
        q.o1 = o1;
        q.o2 = o2;
        q.o3 = o3;
        q.correctHash = _optionHashByIndex(q, correctIndex);
        emit QuestionAdded(_questions.length - 1);
    }

    function _optionHashByIndex(Question storage q, uint8 idx) internal view returns (bytes32) {
        if (idx == 0) return keccak256(bytes(q.o0));
        if (idx == 1) return keccak256(bytes(q.o1));
        if (idx == 2) return keccak256(bytes(q.o2));
        return keccak256(bytes(q.o3));
    }

    function _selectedHash(Question storage q, uint8 selected) internal view returns (bytes32) {
        return _optionHashByIndex(q, selected);
    }

    // ------------------ PoW captcha ------------------
    function powTarget() public view returns (uint256) {
        return type(uint256).max >> powDifficultyBits; // == (2^(256-diff) - 1)
    }

    /**
     * challenge = keccak256( blockhash(challengeBlock) || this || user || userSalt[user] )
     */
    function getChallenge(address user, uint256 challengeBlock) public view returns (bytes32) {
        bytes32 bh = blockhash(challengeBlock);
        require(bh != bytes32(0), "BAD_BLOCKHASH"); // invalid or older than 256 blocks
        return keccak256(abi.encodePacked(bh, address(this), user, userSalt[user]));
    }

    function isValidPoW(address user, uint256 challengeBlock, uint64 powNonce) public view returns (bool) {
        if (challengeBlock >= block.number) return false;
        if (block.number - challengeBlock > maxChallengeAgeBlocks) return false; // your additional window

        bytes32 challenge = getChallenge(user, challengeBlock);
        bytes32 h = keccak256(abi.encodePacked(challenge, powNonce));
        return uint256(h) <= powTarget();
    }

    // ------------------ claim ------------------
    function claim(uint8[] calldata answers, uint256 challengeBlock, uint64 powNonce) external nonReentrant {
        require(!paused, "PAUSED");
        require(!hasClaimed[msg.sender], "ALREADY_CLAIMED");
        require(address(this).balance >= claimAmountWei, "FAUCET_EMPTY");

        require(answers.length == _questions.length, "BAD_LEN");
        for (uint256 i = 0; i < answers.length; i++) {
            require(answers[i] < 4, "BAD_OPT");
            require(_selectedHash(_questions[i], answers[i]) == _questions[i].correctHash, "WRONG_ANSWER");
        }

        require(isValidPoW(msg.sender, challengeBlock, powNonce), "BAD_POW");

        hasClaimed[msg.sender] = true;
        userSalt[msg.sender] += 1;

        (bool ok,) = msg.sender.call{value: claimAmountWei}("");
        require(ok, "SEND_FAIL");

        emit Claimed(msg.sender, claimAmountWei);
    }
}

