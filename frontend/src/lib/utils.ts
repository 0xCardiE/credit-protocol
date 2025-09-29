export function formatUSDC(value: bigint | undefined): string {
  if (value === undefined) return "—";
  const num = Number(value) / 1e6;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(num);
}

export function formatShares(value: bigint | undefined): string {
  if (value === undefined) return "—";
  const num = Number(value) / 1e6;
  return new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  }).format(num);
}

export function formatPercent(bps: bigint | undefined): string {
  if (bps === undefined) return "—";
  return `${(Number(bps) / 100).toFixed(2)}%`;
}

export function formatUtilization(value: bigint | undefined): string {
  if (value === undefined) return "—";
  return `${(Number(value) / 1e16).toFixed(2)}%`;
}

export function parseUSDC(value: string): bigint {
  const num = parseFloat(value);
  if (isNaN(num) || num < 0) return 0n;
  return BigInt(Math.round(num * 1e6));
}

export const LOAN_STATUS_LABELS: Record<number, string> = {
  0: "Created",
  1: "Active",
  2: "Repaid",
  3: "Impaired",
  4: "Defaulted",
};

export const LOAN_STATUS_COLORS: Record<number, string> = {
  0: "bg-slate-100 text-slate-700",
  1: "bg-emerald-100 text-emerald-700",
  2: "bg-blue-100 text-blue-700",
  3: "bg-amber-100 text-amber-700",
  4: "bg-red-100 text-red-700",
};

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatDuration(seconds: number): string {
  const days = Math.floor(seconds / 86400);
  if (days >= 365) return `${(days / 365).toFixed(0)}y`;
  if (days >= 30) return `${(days / 30).toFixed(0)}mo`;
  return `${days}d`;
}
