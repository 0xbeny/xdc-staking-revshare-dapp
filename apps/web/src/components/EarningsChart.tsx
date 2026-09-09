"use client";

import { useQuery } from "@tanstack/react-query";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatUnits } from "viem";
import { fetchPositionEarnings } from "@/lib/indexer";
import styles from "./EarningsChart.module.css";

type Props = {
  tokenId: string;
};

function amountToNumber(raw: string): number {
  try {
    const n = Number(formatUnits(BigInt(raw), 18));
    return Number.isFinite(n) ? n : 0;
  } catch {
    const n = Number(raw);
    return Number.isFinite(n) ? n : 0;
  }
}

export function EarningsChart({ tokenId }: Props) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["earnings", tokenId],
    queryFn: () => fetchPositionEarnings(tokenId),
    staleTime: 30_000,
  });

  const points = (data ?? []).map((p, i) => ({
    label: p.at ? p.at.slice(0, 10) : (p.txHash?.slice(0, 8) ?? `#${i + 1}`),
    amount: amountToNumber(p.amount),
    token: p.token,
  }));

  return (
    <div className={styles.panel}>
      <div className={styles.legend}>
        <span className={styles.swatch} aria-hidden />
        <span>Claimed rewards (indexer)</span>
      </div>
      {isLoading && <p className={styles.empty}>Loading earnings…</p>}
      {isError && <p className={styles.empty}>Could not reach indexer.</p>}
      {!isLoading && !isError && points.length === 0 && (
        <p className={styles.empty}>No indexed data yet</p>
      )}
      {points.length > 0 && (
        <div className={styles.chart}>
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={points} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="earnFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--chart-earnings)" stopOpacity={0.45} />
                  <stop offset="100%" stopColor="var(--chart-earnings)" stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="var(--chart-grid)" vertical={false} />
              <XAxis
                dataKey="label"
                tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                axisLine={false}
                tickLine={false}
                width={48}
              />
              <Tooltip
                contentStyle={{
                  background: "var(--bg-raised)",
                  border: "1px solid var(--border)",
                  borderRadius: 8,
                  color: "var(--ink-primary)",
                }}
              />
              <Area
                type="monotone"
                dataKey="amount"
                name="Amount"
                stroke="var(--chart-earnings)"
                fill="url(#earnFill)"
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}
