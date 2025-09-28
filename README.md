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

# Deploy (local)
anvil &
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Frontend

```bash
cd frontend
npm install
npm run dev
```

Visit `http://localhost:3000` to interact with the protocol.
