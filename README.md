# Credit Protocol — Institutional Credit Vault

An ERC-4626 vault protocol for institutional credit with fixed-term loans, withdrawal queues, and impairment handling.

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│   HoneyVault │────▶│  LoanManager │────▶│ WithdrawalQueue  │
│  (ERC-4626)  │     │              │     │                  │
│  honeyUSDC   │     │  allowlist   │     │  FIFO queue      │
│              │     │  fixed-term  │     │  best-effort     │
└──────────────┘     └──────────────┘     └──────────────────┘
       │                    │
       ▼                    ▼
┌──────────────┐     ┌──────────────┐
│   MockUSDC   │     │  Collateral  │
│   (6 dec)    │     │  (optional)  │
└──────────────┘     └──────────────┘
```

### Key Features

- **ERC-4626 Vault**: deposit/withdraw USDC, receive honeyUSDC shares
- **Institutional Credit**: borrower allowlist, manager-approved loans
- **Fixed-Term Loans**: linear interest accrual, fixed APR and duration
- **NAV Accounting**: `totalAssets = cash + loans - unrealizedLosses`
- **Impairment Flow**: mark impaired → declare default → partial recovery
- **Withdrawal Queue**: when liquidity is insufficient, withdrawals queue FIFO

## Smart Contracts

| Contract | Description |
|---|---|
| `MockUSDC` | 6-decimal ERC-20 with faucet |
| `HoneyVault` | ERC-4626 vault, tracks loans and losses |
| `LoanManager` | Loan lifecycle: create → fund → accrue → repay/default |
| `WithdrawalQueue` | FIFO queue for pending withdrawals |

## Development

```bash
# Build
forge build

# Test
forge test -vvv

# Deploy (local anvil)
anvil &
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

---

## Deployment Guide (Sepolia & Base)

### Prerequisites

| What | Where to get it |
|---|---|
| **Foundry** | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| **Deployer wallet** | Any wallet with testnet ETH. Export the private key. |
| **Sepolia ETH** | [sepoliafaucet.com](https://sepoliafaucet.com) or [cloud.google.com/web3/faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia) |
| **Base Sepolia ETH** | [faucet.base.org](https://www.base.org/faucet) (bridge from Sepolia) |
| **RPC endpoint** | Free tier at [alchemy.com](https://alchemy.com) or [infura.io](https://infura.io) |
| **Etherscan V2 API key** | [etherscan.io/myapikey](https://etherscan.io/myapikey) — one key covers all chains |

### Step 1 — Set up environment variables

```bash
cp .env.example .env
```

Edit `.env` and fill in your values:

```env
PRIVATE_KEY=0xYOUR_DEPLOYER_PRIVATE_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_V2_KEY
```

Then load the env file into your shell:

```bash
source .env
```

### Step 2 — Deploy to Sepolia

```bash
forge script script/Deploy.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

This will:
1. Deploy all 4 contracts (MockUSDC, HoneyVault, LoanManager, WithdrawalQueue)
2. Wire `vault.setLoanManager(...)` automatically
3. Verify all contracts on Etherscan (Sepolia) in one go

### Step 3 — Deploy to Base

```bash
forge script script/Deploy.s.sol \
  --rpc-url base \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

Same flow — deploys and verifies on BaseScan.

### Step 4 — Save deployed addresses

After each deploy, the console output will print the addresses. Copy them into
your frontend `.env.local`:

```bash
# frontend/.env.local
NEXT_PUBLIC_USDC_ADDRESS=0x...
NEXT_PUBLIC_VAULT_ADDRESS=0x...
NEXT_PUBLIC_LOAN_MANAGER_ADDRESS=0x...
NEXT_PUBLIC_WITHDRAWAL_QUEUE_ADDRESS=0x...
```

Also update the chain config in `frontend/src/lib/wagmi.ts` to point
at the correct chain (sepolia or base) instead of `foundry`.

### Verify a single contract manually (if needed)

If auto-verify fails or you want to re-verify later:

```bash
forge verify-contract <DEPLOYED_ADDRESS> src/HoneyVault.sol:HoneyVault \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" <USDC_ADDRESS>)
```

Replace `--chain sepolia` with `--chain base` for Base.

### Troubleshooting

| Problem | Fix |
|---|---|
| `EvmError: OutOfFunds` | Deployer wallet needs more testnet ETH |
| Verification fails with 5xx | Etherscan is congested — wait a minute and run `forge verify-contract` manually |
| `ETHERSCAN_API_KEY` not found | Make sure you ran `source .env` in the same terminal |
| Wrong chain verification URL | Check `foundry.toml` `[etherscan]` section matches the chain you're deploying to |

---

## Frontend

```bash
cd frontend
npm install
npm run dev
```

Visit `http://localhost:3000` to interact with the protocol.
