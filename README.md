# 🔐 TokenSwapEscrow Smart Contract

A secure, decentralized, and customizable **escrow system** for ERC-20 token swaps between two parties. This contract enables two users to safely exchange a set of input tokens for a set of output tokens, with support for deposit tracking, deadlines, dispute resolution, and escrow fee collection.

---

## 📦 Features

- ✅ Two-party ERC20 token swaps with escrow protection  
- 🧾 Multi-token support (up to 10 tokens per side)  
- ⏱️ Customizable deadlines for each escrow (1 hour to 30 days)  
- 💰 Escrow fee mechanism with a configurable fee recipient  
- 🔐 Reentrancy protection, pausable contract, and access control  
- ⚔️ Dispute resolution system (admin resolves disputes)  
- 🔄 Automatic settlement on mutual approval  
- ❌ Escrow cancellation and refund support  
- ⏳ Handles expired escrows with withdrawal support  

---

## 🛠️ Tech Stack

- Solidity ^0.8.19  
- OpenZeppelin Contracts (ERC20, Ownable, ReentrancyGuard, Pausable)  
- Compatible with any EVM-based blockchain (Ethereum, Polygon, BSC, etc.)

---

## 📁 Contract Structure

### Structs

- `TokenAmount`: Represents a token address and amount.
- `EscrowData`: Stores escrow metadata including parties, tokens, approvals, and deadlines.

### Enums

- `EscrowStatus`: Tracks current state (`Created`, `Active`, `Completed`, `Cancelled`, `Disputed`, `Expired`)

---

## 🚀 How It Works

1. **Party A** creates an escrow specifying:
   - Party B's address
   - Token sets from both parties
   - Deadline for the escrow

2. **Both parties deposit** their respective tokens.

3. **Both parties approve** the transaction when ready.

4. If approved before the deadline:
   - Tokens are swapped
   - Fees are deducted and sent to fee recipient

5. If deadline passes without approval:
   - Parties can withdraw their tokens

6. Admin can resolve disputes manually when raised

---

## 💸 Fee Structure

- Default fee: `0.25%` (25 basis points)
- Fee deducted from each token transfer during settlement
- Sent to a configurable `feeRecipient` address

---

## 🔒 Security

- ✅ SafeERC20 token transfers  
- ✅ Reentrancy protection  
- ✅ Only participating parties can interact with specific escrows  
- ✅ Contract can be paused in emergencies  

---

## 📚 Key Functions

| Function | Description |
|----------|-------------|
| `createEscrow()` | Initializes a new escrow |
| `depositTokens()` | Allows each party to deposit tokens |
| `approveEscrow()` | Approves completion of swap |
| `_completeEscrow()` | Internally finalizes and transfers tokens |
| `cancelEscrow()` | Allows cancellation before deposits |
| `withdrawExpired()` | Allows token retrieval if deadline passes |
| `resolveDispute()` | Admin manually resolves disputes |

---

## 🧪 Testing

You should test the following scenarios:

- ✅ Escrow creation with valid/invalid parameters  
- ✅ Token deposit from each party  
- ✅ Double deposit prevention  
- ✅ Approval and finalization flow  
- ✅ Fee calculation accuracy  
- ✅ Expired escrows and token recovery  
- ✅ Dispute resolution outcomes  

Recommended tools: **Hardhat**, **Foundry**, **Remix IDE**

---

## 📌 Deployment

Install dependencies:
```bash
npm install @openzeppelin/contracts
