"use client";

import { abis } from "@vexdc/contracts";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { formatUnits } from "viem";
import {
  useAccount,
  useBalance,
  useReadContract,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import {
  contractsReady,
  estimateLockWeight,
  getConfiguredChainId,
  getContractsState,
  MAX_LOCK_WEEKS,
  MIN_LOCK_WEEKS,
  shareRatio,
  unlockAtWeeks,
  weeksToDuration,
} from "@/lib/contracts";
import {
  formatDate,
  formatRatePct,
  formatUsd,
  formatWeiInput,
  formatXdc,
  formatXdcInputDisplay,
  parseXdcInput,
  txErrorMessage,
} from "@/lib/format";
import { useCorrectChain } from "@/lib/useCorrectChain";
import { useXdcUsdPrice } from "@/lib/useXdcUsdPrice";
import { requestWalletLogin } from "@/lib/walletGate";
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

const MONTH_SHORT = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;
const MONTH_LONG = new Intl.DateTimeFormat("en-US", { month: "long" });
const DOW = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

type CalView = "day" | "month" | "year";

function localDayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function monthStart(y: number, m: number): Date {
  return new Date(y, m, 1);
}

function clampMonth(d: Date, min: Date, max: Date): Date {
  if (d < min) return new Date(min);
  if (d > max) return new Date(max);
  return d;
}

type CalPos = {
  left: number;
  width: number;
  maxHeight?: number;
  top?: number;
  bottom?: number;
};

function headerBottom(): number {
  const header = document.querySelector("header");
  if (header) return header.getBoundingClientRect().bottom;
  const raw = getComputedStyle(document.documentElement).getPropertyValue("--header-h");
  return Number.parseFloat(raw) || 60;
}

function placeCalendar(anchor: HTMLElement): CalPos {
  const rect = anchor.getBoundingClientRect();
  const margin = 12;
  const gap = 8;
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const ceiling = headerBottom() + gap;
  const width = Math.min(Math.max(rect.width, 260), vw - margin * 2);
  let left = rect.left + (rect.width - width) / 2;
  left = Math.min(Math.max(left, margin), vw - margin - width);

  const spaceAbove = rect.top - ceiling;
  const spaceBelow = vh - rect.bottom - margin;
  const preferAbove = spaceAbove >= 180 && spaceAbove >= spaceBelow * 0.7;
  const preferred = 280;

  if (preferAbove) {
    const maxHeight = Math.min(preferred, Math.max(160, spaceAbove - gap));
    return {
      left,
      width,
      bottom: vh - rect.top + gap,
      maxHeight,
    };
  }
  return {
    left,
    width,
    top: rect.bottom + gap,
    maxHeight: Math.min(preferred, Math.max(160, spaceBelow - gap)),
  };
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
  const [balanceUnit, setBalanceUnit] = useState<"xdc" | "usd">("xdc");
  const [pct, setPct] = useState<number | null>(null);
  const [weeks, setWeeks] = useState(52);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [calView, setCalView] = useState<CalView>("day");
  const [calPos, setCalPos] = useState<CalPos | null>(null);
  const [nowSec, setNowSec] = useState<number | null>(null);
  const pickerRef = useRef<HTMLDivElement>(null);
  const dateBtnRef = useRef<HTMLButtonElement>(null);
  const calendarRef = useRef<HTMLDivElement>(null);

  const { writeContract, data: hash, error, isPending, reset } = useWriteContract();
  const {
    isLoading: confirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  const { unlockByDayKey, unlockTs, minMonth, maxMonth } = useMemo(() => {
    const now = nowSec ?? Math.floor(Date.UTC(2026, 0, 1) / 1000);
    const map = new Map<string, { weeks: number; ts: number }>();
    for (let w = MIN_LOCK_WEEKS; w <= MAX_LOCK_WEEKS; w++) {
      const ts = unlockAtWeeks(w, now);
      map.set(localDayKey(new Date(ts * 1000)), { weeks: w, ts });
    }
    const first = new Date(unlockAtWeeks(MIN_LOCK_WEEKS, now) * 1000);
    const last = new Date(unlockAtWeeks(MAX_LOCK_WEEKS, now) * 1000);
    return {
      unlockByDayKey: map,
      unlockTs: unlockAtWeeks(weeks, now),
      minMonth: new Date(first.getFullYear(), first.getMonth(), 1),
      maxMonth: new Date(last.getFullYear(), last.getMonth(), 1),
    };
  }, [weeks, nowSec]);

  const [viewMonth, setViewMonth] = useState(() => {
    const d = new Date(unlockTs * 1000);
    return new Date(d.getFullYear(), d.getMonth(), 1);
  });

  useEffect(() => {
    setNowSec(Math.floor(Date.now() / 1000));
  }, []);

  useEffect(() => {
    if (!pickerOpen) return;
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node;
      if (pickerRef.current?.contains(t) || calendarRef.current?.contains(t)) return;
      setPickerOpen(false);
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

  useLayoutEffect(() => {
    if (!pickerOpen) return;
    const update = () => {
      const el = dateBtnRef.current;
      if (el) setCalPos(placeCalendar(el));
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);
    window.visualViewport?.addEventListener("resize", update);
    window.visualViewport?.addEventListener("scroll", update);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("scroll", update, true);
      window.visualViewport?.removeEventListener("resize", update);
      window.visualViewport?.removeEventListener("scroll", update);
    };
  }, [pickerOpen]);

  useEffect(() => {
    if (isSuccess) {
      setAmount("");
      setPct(null);
    }
  }, [isSuccess]);

  const xdcUsd = useXdcUsdPrice();
  const value = useMemo(() => parseXdcInput(amount), [amount]);
  const amountUsd = useMemo(() => {
    if (xdcUsd == null || value == null || value === 0n) return null;
    return Number(formatUnits(value, 18)) * xdcUsd;
  }, [value, xdcUsd]);
  const balanceUsd = useMemo(() => {
    if (xdcUsd == null || !balance) return null;
    return Number(formatUnits(balance.value, 18)) * xdcUsd;
  }, [balance, xdcUsd]);
  const duration = weeksToDuration(weeks);
  const { data: poolWeight } = useReadContract({
    address: state.deployment.votingEscrow,
    abi: abis.VotingEscrow,
    functionName: "totalSupply",
    query: { enabled: ready, refetchInterval: 15_000 },
  });
  const weightRate = weeks / MAX_LOCK_WEEKS;
  const estimatedWeight =
    value != null && value > 0n
      ? estimateLockWeight(value, unlockTs, nowSec ?? Math.floor(Date.now() / 1000))
      : 0n;
  const shareLabel =
    value == null || value === 0n
      ? "—"
      : poolWeight === undefined
        ? "—"
        : formatRatePct(shareRatio(estimatedWeight, poolWeight));

  const applyPct = (p: number) => {
    reset();
    setPct(p);
    const bal = balance?.value ?? 0n;
    let v = (bal * BigInt(p)) / 100n;
    if (p === 100) v = v > GAS_RESERVE ? v - GAS_RESERVE : 0n;
    setAmount(formatWeiInput(v, 4));
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

  const disabled = !ready || busy || (isConnected && onExpectedChain && invalidAmount);

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

  const yearPageStart = useMemo(() => {
    const y = viewMonth.getFullYear();
    return y - ((y - minMonth.getFullYear()) % 12);
  }, [viewMonth, minMonth]);

  const yearOptions = useMemo(() => {
    return Array.from({ length: 12 }, (_, i) => yearPageStart + i);
  }, [yearPageStart]);

  const canPrev =
    calView === "day"
      ? viewMonth > minMonth
      : calView === "month"
        ? viewMonth.getFullYear() > minMonth.getFullYear()
        : yearPageStart > minMonth.getFullYear();
  const canNext =
    calView === "day"
      ? viewMonth < maxMonth
      : calView === "month"
        ? viewMonth.getFullYear() < maxMonth.getFullYear()
        : yearPageStart + 11 < maxMonth.getFullYear();

  const selectedDate = new Date(unlockTs * 1000);
  const selectedKey = localDayKey(selectedDate);
  const hasBalance = Boolean(isConnected && balance);

  const calTitle =
    calView === "day"
      ? `${MONTH_LONG.format(viewMonth)} ${viewMonth.getFullYear()}`
      : calView === "month"
        ? String(viewMonth.getFullYear())
        : `${yearPageStart} – ${yearPageStart + 11}`;

  const stepCalendar = (dir: -1 | 1) => {
    if (calView === "day") {
      setViewMonth((m) =>
        clampMonth(monthStart(m.getFullYear(), m.getMonth() + dir), minMonth, maxMonth),
      );
      return;
    }
    if (calView === "month") {
      setViewMonth((m) =>
        clampMonth(monthStart(m.getFullYear() + dir, m.getMonth()), minMonth, maxMonth),
      );
      return;
    }
    const next = yearPageStart + dir * 12;
    const targetYear = Math.min(
      Math.max(next, minMonth.getFullYear()),
      maxMonth.getFullYear(),
    );
    setViewMonth((m) =>
      clampMonth(monthStart(targetYear, m.getMonth()), minMonth, maxMonth),
    );
  };

  const openPicker = () => {
    const d = new Date(unlockTs * 1000);
    setViewMonth(new Date(d.getFullYear(), d.getMonth(), 1));
    setCalView("day");
    setPickerOpen((v) => !v);
  };

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
                <span>
                  {balanceUnit === "xdc"
                    ? `${formatXdc(balance!.value)} XDC`
                    : balanceUsd != null
                      ? formatUsd(balanceUsd)
                      : "$—"}
                </span>
                <button
                  type="button"
                  className={styles.unitSwitch}
                  onClick={() => setBalanceUnit((u) => (u === "xdc" ? "usd" : "xdc"))}
                  disabled={xdcUsd == null}
                  title={
                    xdcUsd == null
                      ? "Price unavailable"
                      : balanceUnit === "xdc"
                        ? "Show balance in USD"
                        : "Show balance in XDC"
                  }
                  aria-label={
                    balanceUnit === "xdc" ? "Show balance in USD" : "Show balance in XDC"
                  }
                >
                  <SwitchIcon />
                </button>
              </>
            ) : (
              "Balance —"
            )}
          </span>
        </div>
        <div className={styles.amountBox}>
          <div className={styles.amountMain}>
            <span className={styles.token}>
              <XdcLogo size={32} />
              <span>XDC</span>
            </span>
            <div className={styles.amountValue}>
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
                  setAmount(formatXdcInputDisplay(e.target.value));
                }}
              />
              <span className={styles.amountUsd} aria-live="polite">
                {amountUsd != null ? `≈ ${formatUsd(amountUsd)}` : "≈ $—"}
              </span>
            </div>
            <button
              type="button"
              className={styles.maxBtn}
              disabled={!hasBalance || !balance || balance.value === 0n}
              onClick={() => applyPct(100)}
              aria-label="Use maximum balance"
            >
              MAX
            </button>
          </div>
          <div className={styles.pctInline} role="group" aria-label="Percentage of wallet balance">
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
          ref={dateBtnRef}
          type="button"
          className={styles.dateField}
          aria-expanded={pickerOpen}
          aria-haspopup="dialog"
          onClick={openPicker}
        >
          <span>{formatDate(unlockTs)}</span>
          <span className={styles.dateMeta} aria-hidden>
            <CalendarIcon />
          </span>
        </button>

        {pickerOpen &&
          calPos &&
          createPortal(
            <div
              ref={calendarRef}
              className={styles.calendar}
              role="dialog"
              aria-label="Pick unlock date"
              style={{
                left: calPos.left,
                width: calPos.width,
                maxHeight: calPos.maxHeight,
                top: calPos.top,
                bottom: calPos.bottom,
              }}
            >
              <div className={styles.calSelected}>
                <span className={styles.calSelectedLabel}>Unlock</span>
                <span className={styles.calSelectedValue}>{formatDate(unlockTs)}</span>
              </div>

              <div className={styles.calHead}>
                <button
                  type="button"
                  className={styles.calNav}
                  disabled={!canPrev}
                  onClick={() => stepCalendar(-1)}
                  aria-label={
                    calView === "day"
                      ? "Previous month"
                      : calView === "month"
                        ? "Previous year"
                        : "Previous years"
                  }
                >
                  <ChevronIcon dir="left" />
                </button>
                <button
                  type="button"
                  className={styles.calTitleBtn}
                  onClick={() =>
                    setCalView((v) => (v === "day" ? "month" : v === "month" ? "year" : "year"))
                  }
                  aria-label={
                    calView === "day"
                      ? "Choose month"
                      : calView === "month"
                        ? "Choose year"
                        : "Year range"
                  }
                  disabled={calView === "year"}
                >
                  <span>{calTitle}</span>
                  {calView !== "year" ? <ChevronIcon dir="down" /> : null}
                </button>
                <button
                  type="button"
                  className={styles.calNav}
                  disabled={!canNext}
                  onClick={() => stepCalendar(1)}
                  aria-label={
                    calView === "day"
                      ? "Next month"
                      : calView === "month"
                        ? "Next year"
                        : "Next years"
                  }
                >
                  <ChevronIcon dir="right" />
                </button>
              </div>

              {calView === "day" ? (
                <div className={styles.calBody} key="day">
                  <div className={styles.calGrid}>
                    {DOW.map((d) => (
                      <span key={d} className={styles.calDow}>
                        {d}
                      </span>
                    ))}
                    {calendarCells.map((cell, i) => {
                      if (!cell) return <span key={`e${i}`} className={styles.calDayPad} />;
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
                            setCalView("day");
                          }}
                        >
                          {cell.day}
                        </button>
                      );
                    })}
                  </div>
                  <p className={styles.calHint}>
                    Only week-aligned unlock days are selectable (1 week–2 years).
                  </p>
                </div>
              ) : null}

              {calView === "month" ? (
                <div className={`${styles.calBody} ${styles.calPickerGrid}`} key="month">
                  {MONTH_SHORT.map((label, month) => {
                    const candidate = monthStart(viewMonth.getFullYear(), month);
                    const disabled = candidate < minMonth || candidate > maxMonth;
                    const isActive =
                      selectedDate.getFullYear() === viewMonth.getFullYear() &&
                      selectedDate.getMonth() === month;
                    const isViewing = viewMonth.getMonth() === month;
                    return (
                      <button
                        key={label}
                        type="button"
                        className={`${styles.calPick} ${isActive ? styles.calPickActive : ""} ${isViewing && !isActive ? styles.calPickCurrent : ""}`}
                        disabled={disabled}
                        onClick={() => {
                          setViewMonth(clampMonth(candidate, minMonth, maxMonth));
                          setCalView("day");
                        }}
                      >
                        {label}
                      </button>
                    );
                  })}
                </div>
              ) : null}

              {calView === "year" ? (
                <div className={`${styles.calBody} ${styles.calPickerGrid}`} key="year">
                  {yearOptions.map((year) => {
                    const disabled =
                      year < minMonth.getFullYear() || year > maxMonth.getFullYear();
                    const isActive = selectedDate.getFullYear() === year;
                    const isViewing = viewMonth.getFullYear() === year;
                    return (
                      <button
                        key={year}
                        type="button"
                        className={`${styles.calPick} ${isActive ? styles.calPickActive : ""} ${isViewing && !isActive ? styles.calPickCurrent : ""}`}
                        disabled={disabled}
                        onClick={() => {
                          setViewMonth(
                            clampMonth(
                              monthStart(year, viewMonth.getMonth()),
                              minMonth,
                              maxMonth,
                            ),
                          );
                          setCalView("month");
                        }}
                      >
                        {year}
                      </button>
                    );
                  })}
                </div>
              ) : null}
            </div>,
            document.body,
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
                setCalView("day");
              }}
            >
              {p.label}
            </button>
          ))}
        </div>
        <div className={styles.rateRow}>
          <div className={styles.rateItem} tabIndex={0} aria-describedby="weight-tip">
            <span className={styles.rateLabel}>Weight</span>
            <span className={styles.rateValue}>{formatRatePct(weightRate)}</span>
            <span id="weight-tip" className={styles.rateTip} role="tooltip">
              Of max for this amount
            </span>
          </div>
          <div className={styles.rateItem} tabIndex={0} aria-describedby="share-tip">
            <span className={styles.rateLabel}>Share</span>
            <span className={styles.rateValue}>{shareLabel}</span>
            <span id="share-tip" className={styles.rateTip} role="tooltip">
              Of the pool after you lock. This percentage may adjust over time as more stakers
              interact — it is not fixed.
            </span>
          </div>
        </div>
      </div>

      <div className={styles.footer}>
        <button
          type="button"
          className={styles.submit}
          disabled={disabled}
          onClick={() => {
            if (!isConnected) {
              requestWalletLogin();
              return;
            }
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
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden>
      <rect x="2" y="3.5" width="12" height="10.5" rx="2" stroke="currentColor" strokeWidth="1.4" />
      <path d="M2 6.5h12" stroke="currentColor" strokeWidth="1.4" />
      <path d="M5.5 2v3M10.5 2v3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}

function ChevronIcon({ dir }: { dir: "left" | "right" | "down" }) {
  const rotate = dir === "left" ? 90 : dir === "right" ? -90 : 0;
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden
      style={{ transform: `rotate(${rotate}deg)` }}
    >
      <path
        d="M4 6.5 8 10.5 12 6.5"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function SwitchIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden className={styles.switchIcon}>
      <path
        d="M4.5 5.5h7M9.5 3.5 11.5 5.5 9.5 7.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M11.5 10.5h-7M6.5 8.5 4.5 10.5 6.5 12.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
