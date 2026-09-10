"use client";

import { abis } from "@vexdc/contracts";
import { useEffect, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { ClaimButton } from "@/components/ClaimButton";
import {
  contractsReady,
  getConfiguredChainId,
  getContractsState,
  MAX_LOCK_WEEKS,
  MIN_LOCK_WEEKS,
  weeksToDuration,
} from "@/lib/contracts";
import {
  formatCountdown,
  formatDate,
  formatXdc,
  parseXdcInput,
  txErrorMessage,
  weightHint,
} from "@/lib/format";
import { useCorrectChain } from "@/lib/useCorrectChain";
import styles from "./ManagePosition.module.css";

const ExitKind = {
  None: 0,
  Withdraw: 1,
  Emergency: 2,
} as const;

type Props = {
  tokenId: bigint;
  compact?: boolean;
};

export function ManagePosition({ tokenId, compact = false }: Props) {
  const { address, isConnected } = useAccount();
  const { onExpectedChain, expectedChainId } = useCorrectChain();
  const state = getContractsState();
  const ready = contractsReady(state);
  const writeChainId = getConfiguredChainId();
  const escrow = state.deployment.votingEscrow;
  const zap = state.deployment.zapDepositor;

  const [increaseAmt, setIncreaseAmt] = useState("");
  const [extendWeeks, setExtendWeeks] = useState(52);

  const { data: lock } = useReadContract({
    address: escrow,
    abi: abis.VotingEscrow,
    functionName: "locked",
    args: [tokenId],
    query: { enabled: ready },
  });

  const { data: closed } = useReadContract({
    address: escrow,
    abi: abis.VotingEscrow,
    functionName: "closed",
    args: [tokenId],
    query: { enabled: ready },
  });

  const { data: exit } = useReadContract({
    address: escrow,
    abi: abis.VotingEscrow,
    functionName: "exitRequest",
    args: [tokenId],
    query: { enabled: ready },
  });

  const { data: cooldown } = useReadContract({
    address: escrow,
    abi: abis.VotingEscrow,
    functionName: "withdrawalCooldown",
    query: { enabled: ready },
  });

  const { data: weight } = useReadContract({
    address: escrow,
    abi: abis.VotingEscrow,
    functionName: "balanceOfNFT",
    args: [tokenId],
    query: { enabled: ready },
  });

  const {
    writeContract,
    data: hash,
    error,
    isPending,
    reset,
  } = useWriteContract();
  const {
    isLoading: confirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) setIncreaseAmt("");
  }, [isSuccess]);

  const exitKind = exit ? Number(exit[1]) : ExitKind.None;
  const exitPending = exitKind !== ExitKind.None;
  const readyAt = exit ? Number(exit[0]) : 0;
  const cooldownSec = cooldown !== undefined ? Number(cooldown) : 0;
  const cooldownDone = readyAt > 0 && Date.now() / 1000 >= readyAt;
  const unlockEnd = lock ? Number(lock.end) : 0;
  const matured = unlockEnd > 0 && Date.now() / 1000 >= unlockEnd;
  const isClosed = Boolean(closed);
  const busy = isPending || confirming;
  const writesOk = ready && isConnected && onExpectedChain && !!address && !isClosed;

  const increaseValue = useMemo(() => parseXdcInput(increaseAmt), [increaseAmt]);
  const newUnlock = useMemo(() => {
    const now = Math.floor(Date.now() / 1000);
    return now + Number(weeksToDuration(extendWeeks));
  }, [extendWeeks]);

  const statusMsg = (() => {
    if (!ready) return "Contracts not deployed — writes disabled.";
    if (!isConnected) return "Connect a wallet to manage this position.";
    if (!onExpectedChain) return `Switch wallet to chain ${expectedChainId} before writing.`;
    if (error) return txErrorMessage(error);
    if (receiptError) return txErrorMessage(receiptError);
    if (isPending) return "Confirm in your wallet…";
    if (confirming) return "Waiting for confirmation…";
    if (isSuccess) return "Transaction confirmed.";
    if (exitPending) {
      return cooldownDone
        ? "Cooldown complete — finalize the pending exit."
        : `Exit pending · ready in ${formatCountdown(readyAt)}`;
    }
    return "";
  })();

  const statusClass =
    error || receiptError
      ? styles.statusErr
      : isSuccess
        ? styles.statusOk
        : styles.status;

  function run(fn: () => void) {
    if (!onExpectedChain) return;
    reset();
    fn();
  }

  return (
    <section
      className={`${styles.panel} ${compact ? styles.compact : ""}`}
      aria-labelledby={`manage-${tokenId}`}
    >
      {!compact && (
        <>
          <h2 id={`manage-${tokenId}`} className={styles.title}>
            Manage #{tokenId.toString()}
          </h2>
          <p className={styles.summary}>
            {lock ? `${formatXdc(lock.amount)} XDC` : "—"} locked
            {unlockEnd ? ` · unlock ${formatDate(unlockEnd)}` : ""}
            {weight !== undefined ? ` · weight ${formatXdc(weight, 4)}` : ""}
            {isClosed ? " · closed" : ""}
          </p>
        </>
      )}
      {compact && (
        <h2 id={`manage-${tokenId}`} className={styles.srOnly}>
          Manage #{tokenId.toString()}
        </h2>
      )}

      <div className={styles.groups}>
        <div className={styles.group}>
          <h3 className={styles.groupTitle}>Increase</h3>
          <p className={styles.groupHint}>Add native XDC via Zap (owner only).</p>
          <div className={styles.row}>
            <input
              className={styles.input}
              inputMode="decimal"
              placeholder="Amount XDC"
              aria-label="Increase amount in XDC"
              value={increaseAmt}
              disabled={!writesOk || exitPending || busy}
              onChange={(e) => setIncreaseAmt(e.target.value)}
            />
            <button
              type="button"
              className={styles.secondary}
              disabled={
                !writesOk ||
                exitPending ||
                busy ||
                increaseValue === null ||
                increaseValue === 0n
              }
              onClick={() =>
                run(() =>
                  writeContract({
                    chainId: writeChainId,
                    address: zap,
                    abi: abis.ZapDepositor,
                    functionName: "zapIncreaseAmount",
                    args: [tokenId],
                    value: increaseValue ?? 0n,
                  }),
                )
              }
            >
              Increase
            </button>
          </div>
        </div>

        <div className={styles.group}>
          <h3 className={styles.groupTitle}>Extend</h3>
          <p className={styles.groupHint}>
            {extendWeeks}w from now · {weightHint(extendWeeks)}. Unlock rounds up to a week
            boundary.
          </p>
          <input
            className={styles.slider}
            type="range"
            min={MIN_LOCK_WEEKS}
            max={MAX_LOCK_WEEKS}
            step={1}
            value={extendWeeks}
            disabled={!writesOk || exitPending || busy}
            aria-label="Extend duration in weeks"
            onChange={(e) => setExtendWeeks(Number(e.target.value))}
          />
          <div className={styles.row}>
            <button
              type="button"
              className={styles.secondary}
              disabled={!writesOk || exitPending || busy}
              onClick={() =>
                run(() =>
                  writeContract({
                    chainId: writeChainId,
                    address: escrow,
                    abi: abis.VotingEscrow,
                    functionName: "increaseUnlockTime",
                    args: [tokenId, BigInt(newUnlock)],
                  }),
                )
              }
            >
              Extend to ~{formatDate(newUnlock)}
            </button>
            <button
              type="button"
              className={styles.secondary}
              disabled={!writesOk || exitPending || busy}
              onClick={() =>
                run(() =>
                  writeContract({
                    chainId: writeChainId,
                    address: escrow,
                    abi: abis.VotingEscrow,
                    functionName: "keepAtMaxLock",
                    args: [tokenId],
                  }),
                )
              }
            >
              Max lock ({MAX_LOCK_WEEKS}w)
            </button>
          </div>
        </div>

        <div className={styles.group}>
          <h3 className={styles.groupTitle}>Claim</h3>
          <p className={styles.groupHint}>
            Rewards pay the NFT recipient. Claim &amp; lock compounds WXDC into this position.
          </p>
          <div className={styles.row}>
            <ClaimButton tokenId={tokenId} mode="claim" />
            <ClaimButton tokenId={tokenId} mode="claimAndLock" />
          </div>
        </div>

        <div className={styles.group}>
          <h3 className={styles.groupTitle}>Exit</h3>
          <p className={styles.groupHint}>
            Request → wait cooldown → finalize. Emergency applies a penalty snapshotted at request.
            {cooldownSec > 0
              ? ` Cooldown ${Math.round(cooldownSec / 3600)}h.`
              : " Cooldown is currently 0."}
          </p>

          {exitPending ? (
            <div className={styles.exitPending}>
              <p className={styles.pendingLabel}>
                {exitKind === ExitKind.Emergency ? "Emergency" : "Withdraw"} exit armed
                {readyAt > 0 ? ` · ${formatCountdown(readyAt)}` : ""}
              </p>
              <div className={styles.row}>
                {exitKind === ExitKind.Withdraw && (
                  <button
                    type="button"
                    className={styles.primary}
                    disabled={!writesOk || busy || !cooldownDone}
                    onClick={() =>
                      run(() =>
                        writeContract({
                          chainId: writeChainId,
                          address: escrow,
                          abi: abis.VotingEscrow,
                          functionName: "withdraw",
                          args: [tokenId],
                        }),
                      )
                    }
                  >
                    Finalize withdraw
                  </button>
                )}
                {exitKind === ExitKind.Emergency && (
                  <button
                    type="button"
                    className={styles.primary}
                    disabled={!writesOk || busy || !cooldownDone}
                    onClick={() =>
                      run(() =>
                        writeContract({
                          chainId: writeChainId,
                          address: escrow,
                          abi: abis.VotingEscrow,
                          functionName: "emergencyExit",
                          args: [tokenId],
                        }),
                      )
                    }
                  >
                    Finalize emergency exit
                  </button>
                )}
                <button
                  type="button"
                  className={styles.secondary}
                  disabled={!writesOk || busy}
                  onClick={() =>
                    run(() =>
                      writeContract({
                        chainId: writeChainId,
                        address: escrow,
                        abi: abis.VotingEscrow,
                        functionName: "cancelExitRequest",
                        args: [tokenId],
                      }),
                    )
                  }
                >
                  Cancel exit
                </button>
              </div>
            </div>
          ) : (
            <div className={styles.row}>
              <button
                type="button"
                className={styles.secondary}
                disabled={!writesOk || busy || !matured}
                title={matured ? undefined : "Available after unlock time"}
                onClick={() =>
                  run(() =>
                    writeContract({
                      chainId: writeChainId,
                      address: escrow,
                      abi: abis.VotingEscrow,
                      functionName: "requestWithdraw",
                      args: [tokenId],
                    }),
                  )
                }
              >
                Request withdraw
              </button>
              <button
                type="button"
                className={styles.danger}
                disabled={!writesOk || busy || matured}
                title={matured ? "Lock matured — use withdraw" : undefined}
                onClick={() =>
                  run(() =>
                    writeContract({
                      chainId: writeChainId,
                      address: escrow,
                      abi: abis.VotingEscrow,
                      functionName: "requestEmergencyExit",
                      args: [tokenId],
                    }),
                  )
                }
              >
                Request emergency exit
              </button>
            </div>
          )}
        </div>
      </div>

      <p className={`${styles.status} ${statusClass}`} aria-live="polite">
        {statusMsg}
      </p>
    </section>
  );
}
