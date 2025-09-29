"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import {
  ADDRESSES,
  HONEY_VAULT_ABI,
  MOCK_USDC_ABI,
  WITHDRAWAL_QUEUE_ABI,
} from "@/lib/contracts";
import { formatUSDC, formatShares, parseUSDC } from "@/lib/utils";
import { StatCard } from "@/components/StatCard";

export default function EarnPage() {
  const { address } = useAccount();
  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawShares, setWithdrawShares] = useState("");
  const [mode, setMode] = useState<"deposit" | "withdraw">("deposit");

  const {
    writeContract: writeFaucet,
    data: faucetTxHash,
    isPending: isFaucetPending,
  } = useWriteContract();
  const { isLoading: isFaucetConfirming, isSuccess: faucetSuccess } =
    useWaitForTransactionReceipt({ hash: faucetTxHash });

  const {
    writeContract: writeApprove,
    data: approveTxHash,
    isPending: isApprovePending,
  } = useWriteContract();
  const { isLoading: isApproveConfirming, isSuccess: approveSuccess } =
    useWaitForTransactionReceipt({ hash: approveTxHash });

  const {
    writeContract: writeVault,
    data: vaultTxHash,
    isPending: isVaultPending,
  } = useWriteContract();
  const { isLoading: isVaultConfirming, isSuccess: vaultSuccess } =
    useWaitForTransactionReceipt({ hash: vaultTxHash });

  const { data: usdcBalance, refetch: refetchBalance } = useReadContract({
    address: ADDRESSES.mockUSDC,
    abi: MOCK_USDC_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: shareBalance, refetch: refetchShares } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: usdcAllowance, refetch: refetchAllowance } = useReadContract({
    address: ADDRESSES.mockUSDC,
    abi: MOCK_USDC_ABI,
    functionName: "allowance",
    args: address ? [address, ADDRESSES.honeyVault] : undefined,
    query: { enabled: !!address },
  });

  useEffect(() => {
    if (approveSuccess) {
      refetchAllowance();
    }
  }, [approveSuccess, refetchAllowance]);

  useEffect(() => {
    if (faucetSuccess) {
      refetchBalance();
    }
  }, [faucetSuccess, refetchBalance]);

  useEffect(() => {
    if (vaultSuccess) {
      refetchBalance();
      refetchShares();
      refetchAllowance();
    }
  }, [vaultSuccess, refetchBalance, refetchShares, refetchAllowance]);

  const depositParsed = parseUSDC(depositAmount);
  const withdrawParsed = parseUSDC(withdrawShares);

  const { data: previewDeposit } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "previewDeposit",
    args: [depositParsed],
    query: { enabled: depositParsed > 0n },
  });

  const { data: previewRedeem } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "previewRedeem",
    args: [withdrawParsed],
    query: { enabled: withdrawParsed > 0n },
  });

  const { data: pendingRequests } = useReadContract({
    address: ADDRESSES.withdrawalQueue,
    abi: WITHDRAWAL_QUEUE_ABI,
    functionName: "getUserRequests",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const needsApproval =
    usdcAllowance !== undefined && depositParsed > 0n && usdcAllowance < depositParsed;

  function handleApprove() {
    writeApprove({
      address: ADDRESSES.mockUSDC,
      abi: MOCK_USDC_ABI,
      functionName: "approve",
      args: [ADDRESSES.honeyVault, depositParsed],
    });
  }

  function handleDeposit() {
    if (!address) return;
    writeVault({
      address: ADDRESSES.honeyVault,
      abi: HONEY_VAULT_ABI,
      functionName: "deposit",
      args: [depositParsed, address],
    });
  }

  function handleWithdraw() {
    if (!address) return;
    writeVault({
      address: ADDRESSES.honeyVault,
      abi: HONEY_VAULT_ABI,
      functionName: "redeem",
      args: [withdrawParsed, address, address],
    });
  }

  function handleFaucet() {
    writeFaucet({
      address: ADDRESSES.mockUSDC,
      abi: MOCK_USDC_ABI,
      functionName: "faucet",
      args: [100_000n * 1_000_000n],
    });
  }

  const faucetBusy = isFaucetPending || isFaucetConfirming;
  const approveBusy = isApprovePending || isApproveConfirming;
  const vaultBusy = isVaultPending || isVaultConfirming;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Earn</h1>
        <p className="mt-1 text-sm text-slate-500">
          Deposit USDC to earn yield from institutional loans
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <StatCard label="Your USDC Balance" value={formatUSDC(usdcBalance)} />
        <StatCard label="Your honeyUSDC" value={formatShares(shareBalance)} />
        <StatCard
          label="Pending Withdrawals"
          value={pendingRequests ? pendingRequests.length.toString() : "0"}
          sub="in queue"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-5">
          <div className="flex gap-2">
            <button
              onClick={() => setMode("deposit")}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                mode === "deposit"
                  ? "bg-amber-500 text-white"
                  : "bg-slate-100 text-slate-600 hover:bg-slate-200"
              }`}
            >
              Deposit
            </button>
            <button
              onClick={() => setMode("withdraw")}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                mode === "withdraw"
                  ? "bg-amber-500 text-white"
                  : "bg-slate-100 text-slate-600 hover:bg-slate-200"
              }`}
            >
              Withdraw
            </button>
          </div>

          {mode === "deposit" ? (
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-1">
                  Amount (USDC)
                </label>
                <input
                  type="number"
                  value={depositAmount}
                  onChange={(e) => setDepositAmount(e.target.value)}
                  placeholder="0.00"
                  className="w-full rounded-lg border border-slate-300 px-4 py-3 text-lg focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-transparent"
                />
                {previewDeposit !== undefined && depositParsed > 0n && (
                  <p className="mt-2 text-sm text-slate-500">
                    You will receive{" "}
                    <span className="font-medium text-slate-700">
                      {formatShares(previewDeposit)}
                    </span>{" "}
                    honeyUSDC
                  </p>
                )}
                {usdcAllowance !== undefined && (
                  <p className="mt-1 text-xs text-slate-400">
                    Current approval: {formatUSDC(usdcAllowance)} USDC
                  </p>
                )}
              </div>
              {needsApproval ? (
                <button
                  onClick={handleApprove}
                  disabled={approveBusy}
                  className="w-full py-3 rounded-lg bg-slate-800 text-white font-medium hover:bg-slate-700 disabled:opacity-50 transition-colors"
                >
                  {approveBusy ? "Approving..." : `Approve ${depositAmount || "0"} USDC`}
                </button>
              ) : (
                <button
                  onClick={handleDeposit}
                  disabled={vaultBusy || depositParsed === 0n}
                  className="w-full py-3 rounded-lg bg-amber-500 text-white font-medium hover:bg-amber-600 disabled:opacity-50 transition-colors"
                >
                  {vaultBusy ? "Depositing..." : "Deposit"}
                </button>
              )}
            </div>
          ) : (
            <div className="space-y-4">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <label className="block text-sm font-medium text-slate-700">
                    Shares (honeyUSDC)
                  </label>
                  {shareBalance !== undefined && shareBalance > 0n && (
                    <button
                      onClick={() =>
                        setWithdrawShares((Number(shareBalance) / 1e6).toString())
                      }
                      className="text-xs font-medium text-amber-600 hover:text-amber-700"
                    >
                      MAX
                    </button>
                  )}
                </div>
                <input
                  type="number"
                  value={withdrawShares}
                  onChange={(e) => setWithdrawShares(e.target.value)}
                  placeholder="0.00"
                  className="w-full rounded-lg border border-slate-300 px-4 py-3 text-lg focus:outline-none focus:ring-2 focus:ring-amber-500 focus:border-transparent"
                />
                <p className="mt-2 text-xs text-slate-400">
                  Available: {formatShares(shareBalance)} honeyUSDC
                </p>
                {previewRedeem !== undefined && withdrawParsed > 0n && (
                  <p className="mt-1 text-sm text-slate-500">
                    You will receive{" "}
                    <span className="font-medium text-slate-700">
                      {formatUSDC(previewRedeem)}
                    </span>{" "}
                    USDC
                  </p>
                )}
              </div>
              <button
                onClick={handleWithdraw}
                disabled={vaultBusy || withdrawParsed === 0n}
                className="w-full py-3 rounded-lg bg-amber-500 text-white font-medium hover:bg-amber-600 disabled:opacity-50 transition-colors"
              >
                {vaultBusy ? "Withdrawing..." : "Withdraw"}
              </button>
            </div>
          )}
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h3 className="font-semibold text-slate-900">Testnet Faucet</h3>
          <p className="text-sm text-slate-500">
            Get 100,000 mock USDC to test the protocol.
          </p>
          <button
            onClick={handleFaucet}
            disabled={faucetBusy}
            className="w-full py-3 rounded-lg bg-emerald-500 text-white font-medium hover:bg-emerald-600 disabled:opacity-50 transition-colors"
          >
            {faucetBusy ? "Minting..." : "Get 100K USDC"}
          </button>
        </div>
      </div>
    </div>
  );
}
