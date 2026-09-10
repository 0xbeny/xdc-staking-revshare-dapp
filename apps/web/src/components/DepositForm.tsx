"use client";

import { abis } from "@vexdc/contracts";
import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import {
  contractsReady,
  getConfiguredChainId,
  getContractsState,
  MAX_LOCK_WEEKS,
  MIN_LOCK_WEEKS,
  weeksToDuration,
} from "@/lib/contracts";
import { formatDate, parseXdcInput, txErrorMessage, weightHint } from "@/lib/format";
import { useCorrectChain } from "@/lib/useCorrectChain";
import styles from "./DepositForm.module.css";

export function DepositForm() {
  const { address, isConnected } = useAccount();
  const { onExpectedChain, expectedChainId } = useCorrectChain();
  const state = getContractsState();
  const ready = contractsReady(state);
  const [amount, setAmount] = useState("1000");
  const [weeks, setWeeks] = useState(52);
  const { writeContract, data: hash, error, isPending, reset } = useWriteContract();
  const {
    isLoading: confirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  const value = useMemo(() => parseXdcInput(amount), [amount]);
  const duration = weeksToDuration(weeks);
  const unlockEstimate = Math.floor(Date.now() / 1000) + Number(duration);

  useEffect(() => {
    if (isSuccess) {
      setAmount("");
    }
  }, [isSuccess]);

  const disabled =
    !ready ||
    !isConnected ||
    !onExpectedChain ||
    !address ||
    value === null ||
    value === 0n ||
    isPending ||
    confirming;

  const status = (() => {
    if (!ready) return "Contracts not deployed — deposits disabled.";
    if (!isConnected) return "Connect a wallet to deposit.";
    if (!onExpectedChain) return `Switch wallet to chain ${expectedChainId} before depositing.`;
    if (error) return txErrorMessage(error);
    if (receiptError) return txErrorMessage(receiptError);
    if (isPending) return "Confirm in your wallet…";
    if (confirming) return "Waiting for confirmation…";
    if (isSuccess) return "Lock created. Open Dashboard to manage it.";
    return "Earns from the next epoch snapshot after deposit.";
  })();

  const statusClass =
    error || receiptError
      ? styles.statusErr
      : isSuccess
        ? styles.statusOk
        : styles.status;

  return (
    <section className={styles.panel} id="deposit" aria-labelledby="deposit-title">
      <h2 id="deposit-title" className={styles.title}>
        Lock native XDC
      </h2>
      <p className={styles.hint}>
        Wraps to WXDC via Zap and mints a soulbound veNFT. Duration is whole weeks (1–104).
      </p>

      <div className={styles.field}>
        <div className={styles.labelRow}>
          <label className={styles.label} htmlFor="deposit-amount">
            Amount (XDC)
          </label>
        </div>
        <input
          id="deposit-amount"
          className={styles.input}
          inputMode="decimal"
          autoComplete="off"
          placeholder="0.0"
          value={amount}
          onChange={(e) => {
            reset();
            setAmount(e.target.value);
          }}
        />
      </div>

      <div className={styles.field}>
        <div className={styles.labelRow}>
          <label className={styles.label} htmlFor="deposit-weeks">
            Duration
          </label>
          <span className={styles.meta}>
            {weeks}w · {weightHint(weeks)}
          </span>
        </div>
        <input
          id="deposit-weeks"
          className={styles.slider}
          type="range"
          min={MIN_LOCK_WEEKS}
          max={MAX_LOCK_WEEKS}
          step={1}
          value={weeks}
          onChange={(e) => setWeeks(Number(e.target.value))}
        />
        <p className={styles.unlock}>Est. unlock ≥ {formatDate(unlockEstimate)} (week-aligned)</p>
      </div>

      <div className={styles.footer}>
        <button
          type="button"
          className={styles.submit}
          disabled={disabled}
          onClick={() => {
            if (value === null || value === 0n || !onExpectedChain) return;
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
          {isPending || confirming ? "Depositing…" : "Deposit native XDC"}
        </button>
        <p className={`${styles.status} ${statusClass}`} aria-live="polite">
          {status}
        </p>
      </div>
    </section>
  );
}
