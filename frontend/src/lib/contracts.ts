import { type Address } from "viem";

export const ADDRESSES = {
  mockUSDC: (process.env.NEXT_PUBLIC_USDC_ADDRESS ?? "0x5FbDB2315678afecb367f032d93F642f64180aa3") as Address,
  honeyVault: (process.env.NEXT_PUBLIC_VAULT_ADDRESS ?? "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512") as Address,
  loanManager: (process.env.NEXT_PUBLIC_LOAN_MANAGER_ADDRESS ?? "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0") as Address,
  withdrawalQueue: (process.env.NEXT_PUBLIC_WITHDRAWAL_QUEUE_ADDRESS ?? "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9") as Address,
};

export const MOCK_USDC_ABI = [
  { type: "function", name: "balanceOf", inputs: [{ name: "account", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "approve", inputs: [{ name: "spender", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ name: "", type: "bool" }], stateMutability: "nonpayable" },
  { type: "function", name: "allowance", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "faucet", inputs: [{ name: "amount", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "decimals", inputs: [], outputs: [{ name: "", type: "uint8" }], stateMutability: "pure" },
  { type: "function", name: "symbol", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
] as const;

export const HONEY_VAULT_ABI = [
  { type: "function", name: "totalAssets", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "totalSupply", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "totalLoansPrincipal", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "unrealizedLosses", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "availableLiquidity", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "utilizationRate", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "balanceOf", inputs: [{ name: "account", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "convertToShares", inputs: [{ name: "assets", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "convertToAssets", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "previewDeposit", inputs: [{ name: "assets", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "previewRedeem", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "deposit", inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "redeem", inputs: [{ name: "shares", type: "uint256" }, { name: "receiver", type: "address" }, { name: "owner", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "approve", inputs: [{ name: "spender", type: "address" }, { name: "value", type: "uint256" }], outputs: [{ name: "", type: "bool" }], stateMutability: "nonpayable" },
  { type: "function", name: "manager", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
] as const;

export const LOAN_MANAGER_ABI = [
  { type: "function", name: "getLoan", inputs: [{ name: "loanId", type: "uint256" }], outputs: [{ name: "", type: "tuple", components: [{ name: "borrower", type: "address" }, { name: "principal", type: "uint256" }, { name: "apr", type: "uint256" }, { name: "duration", type: "uint256" }, { name: "collateralToken", type: "address" }, { name: "collateralAmount", type: "uint256" }, { name: "startTime", type: "uint256" }, { name: "interestAccrued", type: "uint256" }, { name: "expectedLoss", type: "uint256" }, { name: "status", type: "uint8" }] }], stateMutability: "view" },
  { type: "function", name: "getLoanCount", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "accrue", inputs: [{ name: "loanId", type: "uint256" }], outputs: [{ name: "interest", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "createLoan", inputs: [{ name: "principal", type: "uint256" }, { name: "apr", type: "uint256" }, { name: "duration", type: "uint256" }, { name: "collateralToken", type: "address" }, { name: "collateralAmount", type: "uint256" }, { name: "borrower", type: "address" }], outputs: [{ name: "loanId", type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "fundLoan", inputs: [{ name: "loanId", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "repay", inputs: [{ name: "loanId", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "markImpaired", inputs: [{ name: "loanId", type: "uint256" }, { name: "expectedLoss", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "declareDefault", inputs: [{ name: "loanId", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "recover", inputs: [{ name: "loanId", type: "uint256" }, { name: "recoveredAmount", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "setAllowedBorrower", inputs: [{ name: "borrower", type: "address" }, { name: "allowed", type: "bool" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "allowedBorrowers", inputs: [{ name: "", type: "address" }], outputs: [{ name: "", type: "bool" }], stateMutability: "view" },
  { type: "function", name: "manager", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
] as const;

export const WITHDRAWAL_QUEUE_ABI = [
  { type: "function", name: "requestWithdrawal", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ name: "requestId", type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "processQueue", inputs: [{ name: "maxCount", type: "uint256" }], outputs: [{ name: "processed", type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "pendingCount", inputs: [], outputs: [{ name: "count", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "getQueueLength", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "getRequest", inputs: [{ name: "requestId", type: "uint256" }], outputs: [{ name: "", type: "tuple", components: [{ name: "owner", type: "address" }, { name: "shares", type: "uint256" }, { name: "timestamp", type: "uint256" }, { name: "fulfilled", type: "bool" }] }], stateMutability: "view" },
  { type: "function", name: "getUserRequests", inputs: [{ name: "user", type: "address" }], outputs: [{ name: "", type: "uint256[]" }], stateMutability: "view" },
] as const;
