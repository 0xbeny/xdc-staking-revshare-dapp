"use client";

import { useQuery } from "@tanstack/react-query";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatUnits } from "viem";
import { fetchProtocolRevenue, fetchProtocolTvl } from "@/lib/indexer";
import { getContractsState } from "@/lib/contracts";
import styles from "./ProtocolCharts.module.css";

function parseAmount(raw: string, decimals: number): number {
  try {
    const n = Number(formatUnits(BigInt(raw), decimals));
    return Number.isFinite(n) ? n : 0;
  } catch {
    const n = Number(raw);
    return Number.isFinite(n) ? n : 0;
  }
}

function decimalsForToken(token: string, usdc?: string): number {
  if (usdc && token.toLowerCase() === usdc.toLowerCase()) return 6;
  return 18;
}

export function ProtocolCharts() {
  const deployment = getContractsState().deployment;
  const tvl = useQuery({
    queryKey: ["protocol-tvl"],
    queryFn: fetchProtocolTvl,
    staleTime: 30_000,
  });
  const revenue = useQuery({
    queryKey: ["protocol-revenue"],
    queryFn: fetchProtocolRevenue,
    staleTime: 30_000,
  });

  const tvlPoints = (tvl.data ?? []).map((p) => ({
    day: p.day,
    totalLocked: parseAmount(p.totalLocked, 18),
  }));

  const revenuePoints = (revenue.data ?? []).map((p) => ({
    label: `e${p.epoch}`,
    revenue: parseAmount(p.revenue, decimalsForToken(p.token, deployment.usdc)),
    token: p.token,
  }));

  return (
    <div className={styles.stack}>
      <section className={styles.panel} aria-labelledby="tvl-chart-title">
        <div className={styles.head}>
          <h3 id="tvl-chart-title" className={styles.title}>
            TVL
          </h3>
          <div className={styles.legend}>
            <span className={`${styles.swatch} ${styles.tvl}`} aria-hidden />
            <span>Total locked</span>
          </div>
        </div>
        {tvl.isLoading && <p className={styles.empty}>Loading TVL…</p>}
        {tvl.isError && <p className={styles.empty}>Could not reach indexer.</p>}
        {!tvl.isLoading && !tvl.isError && tvlPoints.length === 0 && (
          <p className={styles.empty}>No indexed data yet</p>
        )}
        {tvlPoints.length > 0 && (
          <div className={styles.chart}>
            <ResponsiveContainer width="100%" height={200}>
              <AreaChart data={tvlPoints} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="tvlFill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="var(--chart-tvl)" stopOpacity={0.4} />
                    <stop offset="100%" stopColor="var(--chart-tvl)" stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid stroke="var(--chart-grid)" vertical={false} />
                <XAxis
                  dataKey="day"
                  tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                  axisLine={false}
                  tickLine={false}
                  width={52}
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
                  dataKey="totalLocked"
                  name="TVL"
                  stroke="var(--chart-tvl)"
                  fill="url(#tvlFill)"
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}
      </section>

      <section className={styles.panel} aria-labelledby="rev-chart-title">
        <div className={styles.head}>
          <h3 id="rev-chart-title" className={styles.title}>
            Revenue
          </h3>
          <div className={styles.legend}>
            <span className={`${styles.swatch} ${styles.rev}`} aria-hidden />
            <span>Epoch revenue</span>
          </div>
        </div>
        {revenue.isLoading && <p className={styles.empty}>Loading revenue…</p>}
        {revenue.isError && <p className={styles.empty}>Could not reach indexer.</p>}
        {!revenue.isLoading && !revenue.isError && revenuePoints.length === 0 && (
          <p className={styles.empty}>No indexed data yet</p>
        )}
        {revenuePoints.length > 0 && (
          <div className={styles.chart}>
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={revenuePoints} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
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
                  width={52}
                />
                <Tooltip
                  contentStyle={{
                    background: "var(--bg-raised)",
                    border: "1px solid var(--border)",
                    borderRadius: 8,
                    color: "var(--ink-primary)",
                  }}
                />
                <Bar dataKey="revenue" name="Revenue" fill="var(--chart-revenue)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </section>
    </div>
  );
}
