"use client";

import { useState, useEffect, useCallback } from "react";
import { useReadContract } from "wagmi";
import { readContract } from "wagmi/actions";
import { config } from "@/lib/wagmi";
import { ADDRESSES, HONEY_VAULT_ABI, LOAN_MANAGER_ABI, WITHDRAWAL_QUEUE_ABI } from "@/lib/contracts";
import { formatUSDC, formatShares, formatUtilization } from "@/lib/utils";
import { StatCard } from "@/components/StatCard";

interface LoanData {
  status: number;
  principal: bigint;
}

export default function Dashboard() {
  const [totalInterest, setTotalInterest] = useState<bigint>(0n);
  const [activeLoanCount, setActiveLoanCount] = useState(0);

  const { data: totalAssets } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "totalAssets",
  });

  const { data: totalSupply } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "totalSupply",
  });

  const { data: totalLoansPrincipal } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "totalLoansPrincipal",
  });

  const { data: unrealizedLosses } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "unrealizedLosses",
  });

  const { data: availableLiquidity } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "availableLiquidity",
  });

  const { data: utilizationRate } = useReadContract({
    address: ADDRESSES.honeyVault,
    abi: HONEY_VAULT_ABI,
    functionName: "utilizationRate",
  });

  const { data: loanCount } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "getLoanCount",
  });

  const { data: pendingWithdrawals } = useReadContract({
    address: ADDRESSES.withdrawalQueue,
    abi: WITHDRAWAL_QUEUE_ABI,
    functionName: "pendingCount",
  });

  const { data: timeScale } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "timeScale",
  });

  const fetchInterest = useCallback(async () => {
    if (!loanCount) return;
    let interest = 0n;
    let active = 0;
    for (let i = 0; i < Number(loanCount); i++) {
      try {
        const loan = await readContract(config, {
          address: ADDRESSES.loanManager,
          abi: LOAN_MANAGER_ABI,
          functionName: "getLoan",
          args: [BigInt(i)],
        });
        const loanData = loan as LoanData;
        if (loanData.status === 1 || loanData.status === 3) {
          active++;
          const accrued = await readContract(config, {
            address: ADDRESSES.loanManager,
            abi: LOAN_MANAGER_ABI,
            functionName: "accrue",
            args: [BigInt(i)],
          }) as bigint;
          interest += accrued;
        }
      } catch { break; }
    }
    setTotalInterest(interest);
    setActiveLoanCount(active);
  }, [loanCount]);

  useEffect(() => { fetchInterest(); }, [fetchInterest]);

  useEffect(() => {
    if (activeLoanCount === 0) return;
    const interval = setInterval(fetchInterest, 15_000);
    return () => clearInterval(interval);
  }, [activeLoanCount, fetchInterest]);

  const exchangeRate =
    totalAssets !== undefined && totalSupply !== undefined && totalSupply > 0n
      ? (Number(totalAssets) / Number(totalSupply)).toFixed(6)
      : totalSupply === 0n
        ? "1.000000"
        : "—";

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">Dashboard</h1>
        <p className="mt-1 text-sm text-slate-500">Honey Protocol vault overview</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Total Assets (NAV)" value={formatUSDC(totalAssets)} accent />
        <StatCard label="Total Shares" value={formatShares(totalSupply)} sub="honeyUSDC" />
        <StatCard label="Exchange Rate" value={exchangeRate} sub="USDC per honeyUSDC" />
        <StatCard label="Utilization" value={formatUtilization(utilizationRate)} />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard label="Available Liquidity" value={formatUSDC(availableLiquidity)} />
        <StatCard label="Loans Outstanding" value={formatUSDC(totalLoansPrincipal)} />
        <StatCard label="Accrued Interest" value={formatUSDC(totalInterest)} sub="across active loans" accent />
        <StatCard label="Unrealized Losses" value={formatUSDC(unrealizedLosses)} />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Active Loans"
          value={activeLoanCount.toString()}
          sub={`${loanCount ?? 0} total created`}
        />
        <StatCard
          label="Pending Withdrawals"
          value={pendingWithdrawals !== undefined ? pendingWithdrawals.toString() : "0"}
          sub="in queue"
        />
        <StatCard
          label="Time Scale"
          value={timeScale !== undefined ? `${timeScale.toString()}x` : "1x"}
          sub={timeScale !== undefined && timeScale > 1n ? "TURBO MODE" : "Normal"}
        />
      </div>

      <div className="rounded-xl border border-slate-200 bg-white p-6">
        <h2 className="text-lg font-semibold text-slate-900 mb-4">How It Works</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="space-y-2">
            <div className="w-10 h-10 rounded-lg bg-emerald-100 flex items-center justify-center">
              <span className="text-emerald-600 font-bold">1</span>
            </div>
            <h3 className="font-medium text-slate-900">Deposit</h3>
            <p className="text-sm text-slate-500">
              LPs deposit USDC and receive honeyUSDC shares. The exchange rate reflects accrued interest.
            </p>
          </div>
          <div className="space-y-2">
            <div className="w-10 h-10 rounded-lg bg-amber-100 flex items-center justify-center">
              <span className="text-amber-600 font-bold">2</span>
            </div>
            <h3 className="font-medium text-slate-900">Lend</h3>
            <p className="text-sm text-slate-500">
              Approved borrowers receive fixed-term, fixed-rate loans. Interest accrues linearly.
            </p>
          </div>
          <div className="space-y-2">
            <div className="w-10 h-10 rounded-lg bg-blue-100 flex items-center justify-center">
              <span className="text-blue-600 font-bold">3</span>
            </div>
            <h3 className="font-medium text-slate-900">Withdraw</h3>
            <p className="text-sm text-slate-500">
              LPs redeem shares for USDC. If liquidity is low, requests queue and process on repayment.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
