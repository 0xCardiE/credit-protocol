"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useReadContract } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { ADDRESSES, LOAN_MANAGER_ABI } from "@/lib/contracts";

const NAV_ITEMS = [
  { href: "/", label: "Dashboard" },
  { href: "/earn", label: "Earn" },
  { href: "/borrower", label: "Borrower" },
  { href: "/admin", label: "Risk / Admin" },
];

export function Navbar() {
  const pathname = usePathname();

  const { data: timeScale } = useReadContract({
    address: ADDRESSES.loanManager,
    abi: LOAN_MANAGER_ABI,
    functionName: "timeScale",
  });

  const isTurbo = timeScale !== undefined && timeScale > 1n;

  return (
    <nav className="border-b border-slate-200 bg-white/80 backdrop-blur-sm sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center gap-8">
            <Link href="/" className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-400 to-amber-600 flex items-center justify-center">
                <span className="text-white font-bold text-sm">H</span>
              </div>
              <span className="font-semibold text-lg text-slate-900">Honey Protocol</span>
            </Link>
            {isTurbo && (
              <span className="px-2 py-1 text-xs font-bold rounded-full bg-red-500 text-white animate-pulse">
                TURBO {timeScale.toString()}x
              </span>
            )}
            <div className="hidden md:flex items-center gap-1">
              {NAV_ITEMS.map((item) => {
                const isActive = pathname === item.href;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                      isActive
                        ? "bg-amber-50 text-amber-700"
                        : "text-slate-600 hover:text-slate-900 hover:bg-slate-50"
                    }`}
                  >
                    {item.label}
                  </Link>
                );
              })}
            </div>
          </div>
          <ConnectButton />
        </div>
      </div>
    </nav>
  );
}
