# GenesisL1 / L1 Coin Faucet (Quiz + PoW, Browser-Only)

A **client-only** faucet UI + an on-chain **anti-bot gate** for GenesisL1 (**EVM chainId `29`**) that dispenses a small amount of **$L1** per address.

This repo contains:

- **Solidity faucet contract**: one-time claim per address + on-chain quiz + on-chain PoW verification
- **Single-file HTML UI**: no backend, reads faucet stats from `https://rpc.genesisl1.org`, connects to an EVM wallet, solves quiz + PoW in-browser, then sends `claim()`.

> Network: **GenesisL1**  
> RPC: `https://rpc.genesisl1.org`  
> Explorer: `https://explorer.genesisl1.org`  
> chainId: **29** (`0x1d`)  
> Symbol: **L1**

---

## Features

### Contract (Solidity)
- ✅ **One-time claim** per address (`hasClaimed`)
- ✅ **Claim amount configurable** (`claimAmountWei`, default `11 ether`)
- ✅ **Pause control** (`paused`)
- ✅ **Quiz gate on-chain**
  - Question text + 4 options stored on-chain
  - UI verifies each answer via `checkAnswer()` / `validateAll()`
  - Correctness uses `keccak256(option)` stored as `correctHash`
- ✅ **PoW captcha gate on-chain**
  - `challenge = keccak256(blockhash(challengeBlock), contract, user, userSalt[user])`
  - User mines `powNonce` in browser
  - Contract verifies `keccak256(challenge, powNonce) <= target`
  - Target derived from `powDifficultyBits`
  - Challenge expiry bounded by `maxChallengeAgeBlocks` and EVM blockhash window

### UI (HTML, client-only)
- ✅ **No server required**
- ✅ Default-load stats via **public RPC**:
  - last block
  - faucet balance
  - claim amount
- ✅ **Wallet picker** (EIP-6963 + `window.ethereum.providers`)
  - prioritizes MetaMask / Rabby / Coinbase / Brave
  - Keplr excluded (EVM-only UI)
- ✅ “Add GenesisL1 to wallet” button via `wallet_addEthereumChain`
- ✅ “Add via ChainList.org” fallback link
- ✅ In-browser PoW mining using a Web Worker
- ✅ Uses Ethers v6 UMD



