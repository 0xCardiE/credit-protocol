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

  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  const { data: loanCount } = useReadContract({
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
  }, [loanCount, address, txHash]);

  function handleRepay(loanId: number, principal: bigint) {
    if (!address) return;
    writeContract({
      address: ADDRESSES.mockUSDC,
      abi: MOCK_USDC_ABI,
      functionName: "approve",
      args: [ADDRESSES.loanManager, principal * 2n],
    });
    setTimeout(() => {
      writeContract({
        address: ADDRESSES.loanManager,
        abi: LOAN_MANAGER_ABI,
        functionName: "repay",
        args: [BigInt(loanId)],
      });
    }, 2000);
  }

  const busy = isPending || isConfirming;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Borrower</h1>
        <p className="mt-1 text-sm text-slate-500">View your loans and manage repayments</p>
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
            ? "You are an approved borrower. Loans assigned to your address will appear below."
            : "Contact the protocol manager to get added to the borrower allowlist."}
        </p>
      </div>

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
              <div key={id} className="px-6 py-4 flex items-center justify-between">
                <div className="flex items-center gap-6">
                  <div>
                    <p className="text-sm font-medium text-slate-900">Loan #{id}</p>
                    <p className="text-xs text-slate-400">{shortenAddress(data.borrower)}</p>
                  </div>
                  <div>
                    <p className="text-sm text-slate-700">{formatUSDC(data.principal)}</p>
                    <p className="text-xs text-slate-400">Principal</p>
                  </div>
                  <div>
                    <p className="text-sm text-slate-700">{formatPercent(data.apr)}</p>
                    <p className="text-xs text-slate-400">APR</p>
                  </div>
                  <div>
                    <p className="text-sm text-slate-700">{formatDuration(Number(data.duration))}</p>
                    <p className="text-xs text-slate-400">Duration</p>
                  </div>
                  <span
                    className={`px-2 py-1 text-xs font-medium rounded-full ${
                      LOAN_STATUS_COLORS[data.status] ?? ""
                    }`}
                  >
                    {LOAN_STATUS_LABELS[data.status] ?? "Unknown"}
                  </span>
                </div>
                <div>
                  {(data.status === 1 || data.status === 3) && (
                    <button
                      onClick={() => handleRepay(id, data.principal)}
                      disabled={busy}
                      className="px-4 py-2 rounded-lg bg-emerald-500 text-white text-sm font-medium hover:bg-emerald-600 disabled:opacity-50 transition-colors"
                    >
                      {busy ? "Processing..." : "Repay"}
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
