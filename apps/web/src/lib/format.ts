import { formatUnits, type Address } from "viem";

export function shortAddress(address: Address | string, size = 4): string {
  if (address.length < size * 2 + 2) return address;
  return `${address.slice(0, size + 2)}…${address.slice(-size)}`;
}

export function formatXdc(value: bigint, digits = 2): string {
  const n = Number(formatUnits(value, 18));
  if (!Number.isFinite(n)) return "0";
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: digits,
    minimumFractionDigits: 0,
  }).format(n);
}

export function formatUsd(value: number, digits = 2): string {
  if (!Number.isFinite(value)) return "—";
  const abs = Math.abs(value);
  const maxDigits = abs > 0 && abs < 0.01 ? 4 : digits;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: maxDigits,
    minimumFractionDigits: maxDigits === 4 ? 2 : Math.min(digits, 2),
  }).format(value);
}

export function formatTokenAmount(value: bigint, decimals = 18, digits = 4): string {
  const n = Number(formatUnits(value, decimals));
  if (!Number.isFinite(n)) return "0";
  if (n > 0 && n < 1 / 10 ** digits) return `<${1 / 10 ** digits}`;
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: digits,
    minimumFractionDigits: 0,
  }).format(n);
}

export function formatShareBps(bps: number): string {
  const pct = Math.max(0, bps) / 100;
  return `${pct.toFixed(2)}%`;
}

export function formatDate(tsSeconds: number | bigint): string {
  const ms = Number(tsSeconds) * 1000;
  if (!Number.isFinite(ms) || ms <= 0) return "—";
  return new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(ms));
}

export function formatCountdown(readyAtSeconds: number): string {
  const delta = readyAtSeconds * 1000 - Date.now();
  if (delta <= 0) return "Ready now";
  const hours = Math.floor(delta / 3_600_000);
  const mins = Math.floor((delta % 3_600_000) / 60_000);
  if (hours >= 24) {
    const days = Math.floor(hours / 24);
    return `${days}d ${hours % 24}h`;
  }
  return `${hours}h ${mins}m`;
}

export function parseXdcInput(raw: string): bigint | null {
  const trimmed = raw.trim().replace(/,/g, "");
  if (!trimmed || !/^\d+(\.\d{0,18})?$/.test(trimmed)) return null;
  const [whole = "0", frac = ""] = trimmed.split(".");
  const fracPadded = (frac + "0".repeat(18)).slice(0, 18);
  try {
    return BigInt(whole) * 10n ** 18n + BigInt(fracPadded);
  } catch {
    return null;
  }
}

export function weightHint(weeks: number): string {
  const pct = Math.round((Math.min(104, Math.max(1, weeks)) / 104) * 100);
  return `~${pct}% of max weight for this principal`;
}

export function txErrorMessage(error: unknown): string {
  if (!error) return "";
  if (typeof error === "object" && error !== null) {
    const e = error as { shortMessage?: unknown; message?: unknown };
    if (typeof e.shortMessage === "string" && e.shortMessage.length > 0) {
      return e.shortMessage;
    }
    if (typeof e.message === "string" && e.message.length > 0) {
      return e.message;
    }
  }
  return String(error);
}
