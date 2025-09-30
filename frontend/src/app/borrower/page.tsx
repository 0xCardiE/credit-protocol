"use client";

import { useState, useEffect } from "react";
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
  shortenAddress,
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

export default function BorrowerPage() {
  const { address } = useAccount();
  const [loans, setLoans] = useState<{ id: number; data: LoanData }[]>([]);

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

  useEffect(() => {
    if (createSuccess) {
      refetchLoanCount();
    }
  }, [createSuccess, refetchLoanCount]);

  useEffect(() => {
    async function fetchLoans() {
      if (!loanCount || !address) return;

      const results: { id: number; data: LoanData }[] = [];
      for (let i = 0; i < Number(loanCount); i++) {
        try {
          const loan = await readContract(config, {
            address: ADDRESSES.loanManager,
            abi: LOAN_MANAGER_ABI,
            functionName: "getLoan",
            args: [BigInt(i)],
          });
          if ((loan as LoanData).borrower.toLowerCase() === address.toLowerCase()) {
            results.push({ id: i, data: loan as LoanData });
          }
        } catch {
          break;
        }
      }
      setLoans(results);
    }
    fetchLoans();
  }, [loanCount, address, repayTxHash]);

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
        <div className="px-6 py-4 border-b border-slate-200">
          <h2 className="text-lg font-semibold text-slate-900">Your Loans</h2>
        </div>

        {loans.length === 0 ? (
          <div className="px-6 py-12 text-center text-sm text-slate-400">
            No loans found for your address
          </div>
        ) : (
          <div className="divide-y divide-slate-100">
            {loans.map(({ id, data }) => (
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
                  </div>
                  <div className="flex gap-2">
                    {(data.status === 1 || data.status === 3) && !approveSuccess && (
                      <button
                        onClick={() => handleApproveRepay(id, data.principal)}
                        disabled={approveBusy}
                        className="px-4 py-2 rounded-lg bg-slate-800 text-white text-sm font-medium hover:bg-slate-700 disabled:opacity-50 transition-colors"
                      >
                        {approveBusy ? "Approving..." : "Approve Repay"}
                      </button>
                    )}
                    {(data.status === 1 || data.status === 3) && approveSuccess && (
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

                <div className="grid grid-cols-3 gap-4">
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
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
