"use client";

import { abis } from "@vexdc/contracts";
import { useEffect, useMemo, useRef, useState } from "react";
import { formatUnits } from "viem";
import {
  useAccount,
  useBalance,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import {
  contractsReady,
  getConfiguredChainId,
  getContractsState,
  MAX_LOCK_WEEKS,
  MIN_LOCK_WEEKS,
  unlockAtWeeks,
  weeksToDuration,
} from "@/lib/contracts";
import { formatDate, formatXdc, parseXdcInput, txErrorMessage } from "@/lib/format";
import { useCorrectChain } from "@/lib/useCorrectChain";
import { XdcLogo } from "./XdcLogo";
import styles from "./DepositForm.module.css";

/** Keep a little native XDC aside for gas when staking MAX. */
const GAS_RESERVE = 10n ** 18n; // 1 XDC

const PCT_STOPS = [25, 50, 75] as const;

const TERM_PRESETS = [
  { label: "1 week", weeks: 1 },
  { label: "1 month", weeks: 4 },
  { label: "3 months", weeks: 13 },
  { label: "1 year", weeks: 52 },
  { label: "Max", weeks: MAX_LOCK_WEEKS },
] as const;

const MONTH_FMT = new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric" });
const DOW = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

function localDayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

export function DepositForm() {
  const { address, isConnected } = useAccount();
  const { onExpectedChain, expectedChainId } = useCorrectChain();
  const { switchChain, isPending: switching } = useSwitchChain();
  const state = getContractsState();
  const ready = contractsReady(state);
  const { data: balance } = useBalance({
    address,
    chainId: expectedChainId,
    query: { enabled: Boolean(address), refetchInterval: 15_000 },
  });

  const [amount, setAmount] = useState("");
  const [pct, setPct] = useState<number | null>(null);
  const [weeks, setWeeks] = useState(52);
  const [pickerOpen, setPickerOpen] = useState(false);
  const pickerRef = useRef<HTMLDivElement>(null);

  const { writeContract, data: hash, error, isPending, reset } = useWriteContract();
  const {
    isLoading: confirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  const { unlockByDayKey, unlockTs, minMonth, maxMonth } = useMemo(() => {
    const map = new Map<string, { weeks: number; ts: number }>();
    for (let w = MIN_LOCK_WEEKS; w <= MAX_LOCK_WEEKS; w++) {
      const ts = unlockAtWeeks(w);
      map.set(localDayKey(new Date(ts * 1000)), { weeks: w, ts });
    }
    const first = new Date(unlockAtWeeks(MIN_LOCK_WEEKS) * 1000);
    const last = new Date(unlockAtWeeks(MAX_LOCK_WEEKS) * 1000);
    return {
      unlockByDayKey: map,
      unlockTs: unlockAtWeeks(weeks),
      minMonth: new Date(first.getFullYear(), first.getMonth(), 1),
      maxMonth: new Date(last.getFullYear(), last.getMonth(), 1),
    };
  }, [weeks]);

  const [viewMonth, setViewMonth] = useState(() => {
    const d = new Date(unlockTs * 1000);
    return new Date(d.getFullYear(), d.getMonth(), 1);
  });

  useEffect(() => {
    if (!pickerOpen) return;
    const onDown = (e: MouseEvent) => {
      if (pickerRef.current && !pickerRef.current.contains(e.target as Node)) {
        setPickerOpen(false);
      }
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setPickerOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [pickerOpen]);

  useEffect(() => {
    if (isSuccess) {
      setAmount("");
      setPct(null);
    }
  }, [isSuccess]);

  const value = useMemo(() => parseXdcInput(amount), [amount]);
  const duration = weeksToDuration(weeks);
  const weightPct = Math.round((weeks / MAX_LOCK_WEEKS) * 100);

  const applyPct = (p: number) => {
    reset();
    setPct(p);
    const bal = balance?.value ?? 0n;
    let v = (bal * BigInt(p)) / 100n;
    if (p === 100) v = v > GAS_RESERVE ? v - GAS_RESERVE : 0n;
    const s = formatUnits(v, 18);
    const [whole = "0", frac = ""] = s.split(".");
    setAmount(frac ? `${whole}.${frac.slice(0, 4)}`.replace(/\.?0+$/, "") : whole);
  };

  const busy = isPending || confirming || switching;
  const invalidAmount = value === null || value === 0n;

  const buttonLabel = !ready
    ? "Not deployed on this network"
    : !isConnected
      ? "Connect wallet to stake"
      : !onExpectedChain
        ? switching
          ? "Switching…"
          : "Switch network"
        : isPending
          ? "Confirm in wallet…"
          : confirming
            ? "Staking…"
            : "Stake XDC";

  const disabled =
    !ready || !isConnected || !address || busy || (onExpectedChain && invalidAmount);

  const errorText = error
    ? txErrorMessage(error)
    : receiptError
      ? txErrorMessage(receiptError)
      : "";

  const calendarCells = useMemo(() => {
    const year = viewMonth.getFullYear();
    const month = viewMonth.getMonth();
    const firstDow = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const cells: Array<{ day: number; key: string } | null> = [];
    for (let i = 0; i < firstDow; i++) cells.push(null);
    for (let day = 1; day <= daysInMonth; day++) {
      cells.push({ day, key: `${year}-${month}-${day}` });
    }
    return cells;
  }, [viewMonth]);

  const canPrev = viewMonth > minMonth;
  const canNext = viewMonth < maxMonth;
  const selectedKey = localDayKey(new Date(unlockTs * 1000));
  const hasBalance = Boolean(isConnected && balance);

  return (
    <section className={styles.panel} id="deposit" aria-labelledby="deposit-title">
      <h2 id="deposit-title" className={styles.title}>
        Stake XDC
      </h2>

      <div className={styles.field}>
        <div className={styles.labelRow}>
          <label className={styles.label} htmlFor="deposit-amount">
            Amount
          </label>
          <span className={styles.balance}>
            {hasBalance ? (
              <>
                {formatXdc(balance!.value)} XDC
                <button
                  type="button"
                  className={styles.maxBtn}
                  disabled={!balance || balance.value === 0n}
                  onClick={() => applyPct(100)}
                >
                  MAX
                </button>
              </>
            ) : (
              "Balance —"
            )}
          </span>
        </div>
        <div className={styles.amountWrap}>
          <span className={styles.token}>
            <XdcLogo size={22} />
            <span>XDC</span>
          </span>
          <input
            id="deposit-amount"
            className={styles.input}
            inputMode="decimal"
            autoComplete="off"
            placeholder="0.0"
            value={amount}
            onChange={(e) => {
              reset();
              setPct(null);
              setAmount(e.target.value);
            }}
          />
        </div>
        <div className={styles.pctRow}>
          <input
            className={styles.pctSlider}
            type="range"
            min={0}
            max={100}
            step={1}
            value={pct ?? 0}
            disabled={!hasBalance || (balance?.value ?? 0n) === 0n}
            onChange={(e) => applyPct(Number(e.target.value))}
            aria-label="Percentage of wallet balance"
          />
          <div className={styles.pctStops}>
            {PCT_STOPS.map((p) => (
              <button
                key={p}
                type="button"
                className={`${styles.pctChip} ${pct === p ? styles.pctChipActive : ""}`}
                disabled={!hasBalance || (balance?.value ?? 0n) === 0n}
                onClick={() => applyPct(p)}
              >
                {p}%
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className={styles.field} ref={pickerRef}>
        <label className={styles.label} htmlFor="unlock-date">
          Unlock date
        </label>
        <button
          id="unlock-date"
          type="button"
          className={styles.dateField}
          aria-expanded={pickerOpen}
          aria-haspopup="dialog"
          onClick={() => {
            const d = new Date(unlockTs * 1000);
            setViewMonth(new Date(d.getFullYear(), d.getMonth(), 1));
            setPickerOpen((v) => !v);
          }}
        >
          <span>{formatDate(unlockTs)}</span>
          <span className={styles.dateMeta}>
            {weeks}w · ~{weightPct}%
            <CalendarIcon />
          </span>
        </button>

        {pickerOpen && (
          <div className={styles.calendar} role="dialog" aria-label="Pick unlock date">
            <div className={styles.calHead}>
              <button
                type="button"
                className={styles.calNav}
                disabled={!canPrev}
                onClick={() =>
                  setViewMonth(new Date(viewMonth.getFullYear(), viewMonth.getMonth() - 1, 1))
                }
                aria-label="Previous month"
              >
                ‹
              </button>
              <span className={styles.calMonth}>{MONTH_FMT.format(viewMonth)}</span>
              <button
                type="button"
                className={styles.calNav}
                disabled={!canNext}
                onClick={() =>
                  setViewMonth(new Date(viewMonth.getFullYear(), viewMonth.getMonth() + 1, 1))
                }
                aria-label="Next month"
              >
                ›
              </button>
            </div>
            <div className={styles.calGrid}>
              {DOW.map((d) => (
                <span key={d} className={styles.calDow}>
                  {d}
                </span>
              ))}
              {calendarCells.map((cell, i) => {
                if (!cell) return <span key={`e${i}`} />;
                const hit = unlockByDayKey.get(cell.key);
                if (!hit) {
                  return (
                    <span key={cell.key} className={styles.calDayOff}>
                      {cell.day}
                    </span>
                  );
                }
                const isSelected = cell.key === selectedKey;
                return (
                  <button
                    key={cell.key}
                    type="button"
                    className={`${styles.calDay} ${isSelected ? styles.calDaySelected : ""}`}
                    onClick={() => {
                      setWeeks(hit.weeks);
                      setPickerOpen(false);
                    }}
                  >
                    {cell.day}
                  </button>
                );
              })}
            </div>
            <p className={styles.calHint}>
              Highlighted days are week-aligned unlocks (1–104 weeks). Grey days are not
              available.
            </p>
          </div>
        )}
        <div className={styles.termStops} role="group" aria-label="Lock term">
          {TERM_PRESETS.map((p) => (
            <button
              key={p.label}
              type="button"
              className={`${styles.termChip} ${weeks === p.weeks ? styles.termChipActive : ""}`}
              onClick={() => {
                setWeeks(p.weeks);
                const d = new Date(unlockAtWeeks(p.weeks) * 1000);
                setViewMonth(new Date(d.getFullYear(), d.getMonth(), 1));
              }}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      <div className={styles.footer}>
        <button
          type="button"
          className={styles.submit}
          disabled={disabled}
          onClick={() => {
            if (!onExpectedChain) {
              switchChain({ chainId: expectedChainId });
              return;
            }
            if (value === null || value === 0n) return;
            writeContract({
              address: state.deployment.zapDepositor,
              abi: abis.ZapDepositor,
              functionName: "zapCreateLock",
              args: [duration],
              value,
              chainId: getConfiguredChainId(),
            });
          }}
        >
          {buttonLabel}
        </button>
        {(errorText || isSuccess) && (
          <p className={errorText ? styles.statusErr : styles.statusOk} aria-live="polite">
            {errorText || "Staked. Manage your position from the Dashboard."}
          </p>
        )}
      </div>
    </section>
  );
}

function CalendarIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden>
      <rect x="2" y="3.5" width="12" height="10.5" rx="2" stroke="currentColor" strokeWidth="1.4" />
      <path d="M2 6.5h12" stroke="currentColor" strokeWidth="1.4" />
      <path d="M5.5 2v3M10.5 2v3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}
