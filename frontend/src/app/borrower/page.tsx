"use client";

import { useState, useEffect, useCallback } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { readContract } from "wagmi/actions";
import { config } from "@/lib/wagmi";
import { zeroAddress } from "viem";
import {
  ADDRESSES,
  LOAN_MANAGER_ABI,
  MOCK_USDC_ABI,
} from "@/lib/contracts";
import {
  formatUSDC,
  formatPercent,
  formatDuration,
  parseUSDC,
  LOAN_STATUS_LABELS,
  LOAN_STATUS_COLORS,
} from "@/lib/utils";

interface LoanData {
  borrower: string;
  principal: bigint;
  apr: bigint;
  duration: bigint;
  collateralToken: string;
  collateralAmount: bigint;
  startTime: bigint;
  interestAccrued: bigint;
  expectedLoss: bigint;
  status: number;
}

interface LoanWithInterest {
  id: number;
  data: LoanData;
  accruedInterest: bigint;
}

export default function BorrowerPage() {
  const { address } = useAccount();
  const [loans, setLoans] = useState<LoanWithInterest[]>([]);

  const [loanPrincipal, setLoanPrincipal] = useState("");
  const [loanApr, setLoanApr] = useState("1000");
  const [loanDuration, setLoanDuration] = useState("180");

  const {
    writeContract: writeCreate,
    data: createTxHash,
    isPending: isCreatePending,
  } = useWriteContract();
  const { isLoading: isCreateConfirming, isSuccess: createSuccess } =
    useWaitForTransactionReceipt({ hash: createTxHash });

  const {
    writeContract: writeRepay,
    data: repayTxHash,
    isPending: isRepayPending,
  } = useWriteContract();
  const { isLoading: isRepayConfirming } =
    useWaitForTransactionReceipt({ hash: repayTxHash });

  const {
    writeContract: writeApprove,
    data: approveTxHash,
    isPending: isApprovePending,
  } = useWriteContract();
  const { isLoading: isApproveConfirming, isSuccess: approveSuccess } =
    useWaitForTransactionReceipt({ hash: approveTxHash });

  const { data: loanCount, refetch: refetchLoanCount } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "getLoanCount",
  });

  const { data: isAllowed } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "allowedBorrowers",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: timeScale } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "timeScale",
  });

  useEffect(() => {
    if (createSuccess) {
      refetchLoanCount();
    }
  }, [createSuccess, refetchLoanCount]);

  const fetchLoans = useCallback(async () => {
    if (!loanCount || !address) return;

    const results: LoanWithInterest[] = [];
    for (let i = 0; i < Number(loanCount); i++) {
      try {
        const loan = await readContract(config, {
          address: ADDRESSES.loanManager,
          abi: LOAN_MANAGER_ABI,
          functionName: "getLoan",
          args: [BigInt(i)],
        });
        const loanData = loan as LoanData;
        if (loanData.borrower.toLowerCase() !== address.toLowerCase()) continue;

        let accruedInterest = 0n;
        if (loanData.status === 1 || loanData.status === 3) {
          try {
            accruedInterest = await readContract(config, {
              address: ADDRESSES.loanManager,
              abi: LOAN_MANAGER_ABI,
              functionName: "accrue",
              args: [BigInt(i)],
            }) as bigint;
          } catch {}
        }
        results.push({ id: i, data: loanData, accruedInterest });
      } catch {
        break;
      }
    }
    setLoans(results);
  }, [loanCount, address]);

  useEffect(() => {
    fetchLoans();
  }, [fetchLoans, repayTxHash]);

  // Auto-refresh every 10s for live interest updates
  useEffect(() => {
    const hasActiveLoans = loans.some((l) => l.data.status === 1 || l.data.status === 3);
    if (!hasActiveLoans) return;
    const interval = setInterval(fetchLoans, 10_000);
    return () => clearInterval(interval);
  }, [loans, fetchLoans]);

  function handleRequestLoan() {
    if (!address) return;
    writeCreate({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "createLoan",
      args: [
        parseUSDC(loanPrincipal),
        BigInt(loanApr),
        BigInt(Number(loanDuration) * 86400),
        zeroAddress,
        0n,
        address,
      ],
    });
  }

  function handleApproveRepay(loanId: number, principal: bigint) {
    writeApprove({
      address: ADDRESSES.mockUSDC,
      abi: MOCK_USDC_ABI,
      functionName: "approve",
      args: [ADDRESSES.loanManager, principal * 2n],
    });
  }

  function handleRepay(loanId: number) {
    writeRepay({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "repay",
      args: [BigInt(loanId)],
    });
  }

  const createBusy = isCreatePending || isCreateConfirming;
  const approveBusy = isApprovePending || isApproveConfirming;
  const repayBusy = isRepayPending || isRepayConfirming;
  const isTurbo = timeScale !== undefined && timeScale > 1n;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Borrower</h1>
        <p className="mt-1 text-sm text-slate-500">Request loans and manage repayments</p>
      </div>

      <div className="rounded-xl border border-slate-200 bg-white p-6">
        <div className="flex items-center gap-3 mb-4">
          <h2 className="text-lg font-semibold text-slate-900">Allowlist Status</h2>
          {isAllowed ? (
            <span className="px-2 py-1 text-xs font-medium rounded-full bg-emerald-100 text-emerald-700">
              Approved
            </span>
          ) : (
            <span className="px-2 py-1 text-xs font-medium rounded-full bg-red-100 text-red-700">
              Not Approved
            </span>
          )}
        </div>
        <p className="text-sm text-slate-500">
          {isAllowed
            ? "You are an approved borrower. Submit a loan request below — the protocol manager will review and fund it."
            : "Contact the protocol manager to get added to the borrower allowlist."}
        </p>
      </div>

      {isAllowed && (
        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">Request Loan</h2>
          <p className="text-sm text-slate-500">
            Submit your loan terms. Once created, the manager will review and fund it.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                Principal (USDC)
              </label>
              <input
                type="number"
                value={loanPrincipal}
                onChange={(e) => setLoanPrincipal(e.target.value)}
                placeholder="100000"
                className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                APR (bps)
              </label>
              <input
                type="number"
                value={loanApr}
                onChange={(e) => setLoanApr(e.target.value)}
                placeholder="1000"
                className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
              <p className="mt-1 text-xs text-slate-400">
                {(Number(loanApr) / 100).toFixed(2)}%
              </p>
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">
                Duration (days)
              </label>
              <input
                type="number"
                value={loanDuration}
                onChange={(e) => setLoanDuration(e.target.value)}
                placeholder="180"
                className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
            </div>
          </div>
          <button
            onClick={handleRequestLoan}
            disabled={createBusy || !loanPrincipal}
            className="w-full py-3 rounded-lg bg-amber-500 text-white font-medium hover:bg-amber-600 disabled:opacity-50 transition-colors"
          >
            {createBusy ? "Submitting..." : "Request Loan"}
          </button>
        </div>
      )}

      <div className="rounded-xl border border-slate-200 bg-white overflow-hidden">
        <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-slate-900">Your Loans</h2>
          {isTurbo && (
            <span className="text-xs text-red-500 font-medium">
              Auto-refreshing every 10s
            </span>
          )}
        </div>

        {loans.length === 0 ? (
          <div className="px-6 py-12 text-center text-sm text-slate-400">
            No loans found for your address
          </div>
        ) : (
          <div className="divide-y divide-slate-100">
            {loans.map(({ id, data, accruedInterest }) => {
              const isActive = data.status === 1 || data.status === 3;
              const totalOwed = isActive ? data.principal + accruedInterest : 0n;
              const elapsed = isActive && data.startTime > 0n
                ? Number(accruedInterest) > 0
                  ? Math.min(
                      Math.round((Number(accruedInterest) * 365 * 86400 * 10000) / (Number(data.principal) * Number(data.apr))),
                      Number(data.duration)
                    )
                  : 0
                : 0;
              const progress = isActive ? Math.min((elapsed / Number(data.duration)) * 100, 100) : 0;
              const isMatured = progress >= 100;

              return (
                <div
                  key={id}
                  className={`px-6 py-5 ${data.status === 0 ? "bg-amber-50/40" : ""}`}
                >
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-3">
                      <h3 className="text-sm font-semibold text-slate-900">Loan #{id}</h3>
                      <span
                        className={`px-2.5 py-1 text-xs font-medium rounded-full ${
                          LOAN_STATUS_COLORS[data.status] ?? ""
                        }`}
                      >
                        {LOAN_STATUS_LABELS[data.status] ?? "Unknown"}
                      </span>
                      {isMatured && isActive && (
                        <span className="px-2 py-1 text-xs font-medium rounded-full bg-blue-100 text-blue-700">
                          Matured
                        </span>
                      )}
                    </div>
                    <div className="flex gap-2">
                      {isActive && !approveSuccess && (
                        <button
                          onClick={() => handleApproveRepay(id, data.principal)}
                          disabled={approveBusy}
                          className="px-4 py-2 rounded-lg bg-slate-800 text-white text-sm font-medium hover:bg-slate-700 disabled:opacity-50 transition-colors"
                        >
                          {approveBusy ? "Approving..." : "Approve Repay"}
                        </button>
                      )}
                      {isActive && approveSuccess && (
                        <button
                          onClick={() => handleRepay(id)}
                          disabled={repayBusy}
                          className="px-4 py-2 rounded-lg bg-emerald-500 text-white text-sm font-medium hover:bg-emerald-600 disabled:opacity-50 transition-colors"
                        >
                          {repayBusy ? "Repaying..." : "Repay"}
                        </button>
                      )}
                    </div>
                  </div>

                  {data.status === 0 && (
                    <div className="mb-3 flex items-center gap-2 text-xs text-amber-700 bg-amber-100 rounded-lg px-3 py-2">
                      <svg className="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                      </svg>
                      Awaiting manager approval — loan has not been funded yet.
                    </div>
                  )}

                  <div className="grid grid-cols-3 gap-4 mb-3">
                    <div className="bg-slate-50 rounded-lg px-3 py-2">
                      <p className="text-xs text-slate-400 mb-0.5">Principal</p>
                      <p className="text-sm font-medium text-slate-800">{formatUSDC(data.principal)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg px-3 py-2">
                      <p className="text-xs text-slate-400 mb-0.5">APR</p>
                      <p className="text-sm font-medium text-slate-800">{formatPercent(data.apr)}</p>
                    </div>
                    <div className="bg-slate-50 rounded-lg px-3 py-2">
                      <p className="text-xs text-slate-400 mb-0.5">Duration</p>
                      <p className="text-sm font-medium text-slate-800">{formatDuration(Number(data.duration))}</p>
                    </div>
                  </div>

                  {isActive && (
                    <>
                      <div className="grid grid-cols-3 gap-4 mb-3">
                        <div className="bg-amber-50 rounded-lg px-3 py-2 border border-amber-100">
                          <p className="text-xs text-amber-600 mb-0.5">Accrued Interest</p>
                          <p className="text-sm font-semibold text-amber-800">{formatUSDC(accruedInterest)}</p>
                        </div>
                        <div className="bg-red-50 rounded-lg px-3 py-2 border border-red-100">
                          <p className="text-xs text-red-600 mb-0.5">Total Owed</p>
                          <p className="text-sm font-semibold text-red-800">{formatUSDC(totalOwed)}</p>
                        </div>
                        <div className="bg-blue-50 rounded-lg px-3 py-2 border border-blue-100">
                          <p className="text-xs text-blue-600 mb-0.5">Time Elapsed</p>
                          <p className="text-sm font-semibold text-blue-800">
                            {formatDuration(elapsed)} / {formatDuration(Number(data.duration))}
                          </p>
                        </div>
                      </div>
                      <div className="w-full bg-slate-200 rounded-full h-2">
                        <div
                          className={`h-2 rounded-full transition-all ${isMatured ? "bg-blue-500" : "bg-amber-500"}`}
                          style={{ width: `${progress}%` }}
                        />
                      </div>
                      <p className="text-xs text-slate-400 mt-1 text-right">{progress.toFixed(1)}% complete</p>
                    </>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
