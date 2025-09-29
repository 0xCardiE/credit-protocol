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
import { type Address, zeroAddress } from "viem";
import {
  ADDRESSES,
  LOAN_MANAGER_ABI,
  MOCK_USDC_ABI,
  WITHDRAWAL_QUEUE_ABI,
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

export default function AdminPage() {
  const { address } = useAccount();
  const [loans, setLoans] = useState<{ id: number; data: LoanData }[]>([]);

  const [newBorrower, setNewBorrower] = useState("");
  const [loanBorrower, setLoanBorrower] = useState("");
  const [loanPrincipal, setLoanPrincipal] = useState("");
  const [loanApr, setLoanApr] = useState("1000");
  const [loanDuration, setLoanDuration] = useState("180");
  const [impairLoanId, setImpairLoanId] = useState("");
  const [impairLoss, setImpairLoss] = useState("");
  const [recoverLoanId, setRecoverLoanId] = useState("");
  const [recoverAmount, setRecoverAmount] = useState("");

  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  const { data: loanCount } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "getLoanCount",
  });

  const { data: managerAddr } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "manager",
  });

  const { data: pendingCount } = useReadContract({
    address: ADDRESSES.withdrawalQueue,
    abi: WITHDRAWAL_QUEUE_ABI,
    functionName: "pendingCount",
  });

  const isManager = address && managerAddr && address.toLowerCase() === (managerAddr as string).toLowerCase();

  useEffect(() => {
    async function fetchLoans() {
      if (!loanCount) return;
      const results: { id: number; data: LoanData }[] = [];
      for (let i = 0; i < Number(loanCount); i++) {
        try {
          const loan = await readContract(config, {
            address: ADDRESSES.loanManager,
            abi: LOAN_MANAGER_ABI,
            functionName: "getLoan",
            args: [BigInt(i)],
          });
          results.push({ id: i, data: loan as LoanData });
        } catch {
          break;
        }
      }
      setLoans(results);
    }
    fetchLoans();
  }, [loanCount, txHash]);

  const busy = isPending || isConfirming;

  function handleAllowBorrower() {
    writeContract({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "setAllowedBorrower",
      args: [newBorrower as Address, true],
    });
  }

  function handleCreateLoan() {
    writeContract({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "createLoan",
      args: [
        parseUSDC(loanPrincipal),
        BigInt(loanApr),
        BigInt(Number(loanDuration) * 86400),
        zeroAddress,
        0n,
        loanBorrower as Address,
      ],
    });
  }

  function handleFundLoan(loanId: number) {
    writeContract({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "fundLoan",
      args: [BigInt(loanId)],
    });
  }

  function handleMarkImpaired() {
    writeContract({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "markImpaired",
      args: [BigInt(impairLoanId), parseUSDC(impairLoss)],
    });
  }

  function handleDeclareDefault(loanId: number) {
    writeContract({
      address: ADDRESSES.loanManager,
      abi: LOAN_MANAGER_ABI,
      functionName: "declareDefault",
      args: [BigInt(loanId)],
    });
  }

  function handleRecover() {
    const amount = parseUSDC(recoverAmount);
    writeContract({
      address: ADDRESSES.mockUSDC,
      abi: MOCK_USDC_ABI,
      functionName: "approve",
      args: [ADDRESSES.loanManager, amount],
    });
    setTimeout(() => {
      writeContract({
        address: ADDRESSES.loanManager,
        abi: LOAN_MANAGER_ABI,
        functionName: "recover",
        args: [BigInt(recoverLoanId), amount],
      });
    }, 2000);
  }

  function handleProcessQueue() {
    writeContract({
      address: ADDRESSES.withdrawalQueue,
      abi: WITHDRAWAL_QUEUE_ABI,
      functionName: "processQueue",
      args: [10n],
    });
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Risk / Admin</h1>
        <p className="mt-1 text-sm text-slate-500">
          Manage borrowers, loans, impairments, and the withdrawal queue
        </p>
        {!isManager && address && (
          <div className="mt-3 rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm text-amber-700">
            Your connected wallet is not the protocol manager. Write operations will revert.
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Borrower Allowlist */}
        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">Borrower Allowlist</h2>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Borrower Address</label>
            <input
              type="text"
              value={newBorrower}
              onChange={(e) => setNewBorrower(e.target.value)}
              placeholder="0x..."
              className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
            />
          </div>
          <button
            onClick={handleAllowBorrower}
            disabled={busy || !newBorrower}
            className="w-full py-2 rounded-lg bg-slate-800 text-white text-sm font-medium hover:bg-slate-700 disabled:opacity-50 transition-colors"
          >
            {busy ? "Processing..." : "Add to Allowlist"}
          </button>
        </div>

        {/* Create Loan */}
        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">Create Loan</h2>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="block text-sm font-medium text-slate-700 mb-1">Borrower</label>
              <input
                type="text"
                value={loanBorrower}
                onChange={(e) => setLoanBorrower(e.target.value)}
                placeholder="0x..."
                className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Principal (USDC)</label>
              <input
                type="number"
                value={loanPrincipal}
                onChange={(e) => setLoanPrincipal(e.target.value)}
                placeholder="100000"
                className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">APR (bps)</label>
              <input
                type="number"
                value={loanApr}
                onChange={(e) => setLoanApr(e.target.value)}
                placeholder="1000"
                className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
              />
              <p className="mt-1 text-xs text-slate-400">{(Number(loanApr) / 100).toFixed(2)}%</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Duration (days)</label>
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
            onClick={handleCreateLoan}
            disabled={busy || !loanBorrower || !loanPrincipal}
            className="w-full py-2 rounded-lg bg-amber-500 text-white text-sm font-medium hover:bg-amber-600 disabled:opacity-50 transition-colors"
          >
            {busy ? "Processing..." : "Create Loan"}
          </button>
        </div>
      </div>

      {/* Impairment & Recovery */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">Mark Impaired</h2>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Loan ID</label>
            <input
              type="number"
              value={impairLoanId}
              onChange={(e) => setImpairLoanId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Expected Loss (USDC)</label>
            <input
              type="number"
              value={impairLoss}
              onChange={(e) => setImpairLoss(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
            />
          </div>
          <button
            onClick={handleMarkImpaired}
            disabled={busy || !impairLoanId || !impairLoss}
            className="w-full py-2 rounded-lg bg-amber-600 text-white text-sm font-medium hover:bg-amber-700 disabled:opacity-50 transition-colors"
          >
            Mark Impaired
          </button>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">Recovery</h2>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Loan ID</label>
            <input
              type="number"
              value={recoverLoanId}
              onChange={(e) => setRecoverLoanId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Recovered Amount (USDC)</label>
            <input
              type="number"
              value={recoverAmount}
              onChange={(e) => setRecoverAmount(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500"
            />
          </div>
          <button
            onClick={handleRecover}
            disabled={busy || !recoverLoanId || !recoverAmount}
            className="w-full py-2 rounded-lg bg-emerald-500 text-white text-sm font-medium hover:bg-emerald-600 disabled:opacity-50 transition-colors"
          >
            Apply Recovery
          </button>
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-6 space-y-4">
          <h2 className="text-lg font-semibold text-slate-900">Withdrawal Queue</h2>
          <p className="text-sm text-slate-500">
            <span className="font-medium text-slate-700">{pendingCount?.toString() ?? "0"}</span> pending requests
          </p>
          <button
            onClick={handleProcessQueue}
            disabled={busy}
            className="w-full py-2 rounded-lg bg-blue-500 text-white text-sm font-medium hover:bg-blue-600 disabled:opacity-50 transition-colors"
          >
            Process Queue (up to 10)
          </button>
        </div>
      </div>

      {/* All Loans Table */}
      <div className="rounded-xl border border-slate-200 bg-white overflow-hidden">
        <div className="px-6 py-4 border-b border-slate-200">
          <h2 className="text-lg font-semibold text-slate-900">All Loans</h2>
        </div>

        {loans.length === 0 ? (
          <div className="px-6 py-12 text-center text-sm text-slate-400">No loans created yet</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-slate-100 text-left">
                  <th className="px-6 py-3 font-medium text-slate-500">ID</th>
                  <th className="px-6 py-3 font-medium text-slate-500">Borrower</th>
                  <th className="px-6 py-3 font-medium text-slate-500">Principal</th>
                  <th className="px-6 py-3 font-medium text-slate-500">APR</th>
                  <th className="px-6 py-3 font-medium text-slate-500">Duration</th>
                  <th className="px-6 py-3 font-medium text-slate-500">Status</th>
                  <th className="px-6 py-3 font-medium text-slate-500">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-50">
                {loans.map(({ id, data }) => (
                  <tr key={id} className="hover:bg-slate-50/50">
                    <td className="px-6 py-3 font-mono text-slate-700">#{id}</td>
                    <td className="px-6 py-3 font-mono text-slate-600">{shortenAddress(data.borrower)}</td>
                    <td className="px-6 py-3 text-slate-700">{formatUSDC(data.principal)}</td>
                    <td className="px-6 py-3 text-slate-700">{formatPercent(data.apr)}</td>
                    <td className="px-6 py-3 text-slate-700">{formatDuration(Number(data.duration))}</td>
                    <td className="px-6 py-3">
                      <span className={`px-2 py-1 text-xs font-medium rounded-full ${LOAN_STATUS_COLORS[data.status]}`}>
                        {LOAN_STATUS_LABELS[data.status]}
                      </span>
                    </td>
                    <td className="px-6 py-3">
                      <div className="flex gap-2">
                        {data.status === 0 && (
                          <button
                            onClick={() => handleFundLoan(id)}
                            disabled={busy}
                            className="px-3 py-1 rounded bg-emerald-500 text-white text-xs font-medium hover:bg-emerald-600 disabled:opacity-50"
                          >
                            Fund
                          </button>
                        )}
                        {(data.status === 1 || data.status === 3) && (
                          <button
                            onClick={() => handleDeclareDefault(id)}
                            disabled={busy}
                            className="px-3 py-1 rounded bg-red-500 text-white text-xs font-medium hover:bg-red-600 disabled:opacity-50"
                          >
                            Default
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
