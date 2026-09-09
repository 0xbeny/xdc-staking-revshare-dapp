"use client";

import { abis } from "@vexdc/contracts";
import { useMemo } from "react";
import type { Address } from "viem";
import {
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { contractsReady, getContractsState } from "@/lib/contracts";
import { txErrorMessage } from "@/lib/format";
import styles from "./ClaimButton.module.css";

type Props = {
  tokenId: bigint;
  mode?: "claim" | "claimAndLock";
};

export function ClaimButton({ tokenId, mode = "claim" }: Props) {
  const state = getContractsState();
  const ready = contractsReady(state);
  const { data: rewardTokens } = useReadContract({
    address: state.deployment.feeDistributor,
    abi: abis.FeeDistributor,
    functionName: "rewardTokens",
    query: { enabled: ready },
  });

  const tokens = useMemo((): Address[] => {
    if (rewardTokens && rewardTokens.length > 0) {
      return [...rewardTokens] as Address[];
    }
    return [state.deployment.wxdc];
  }, [rewardTokens, state.deployment.wxdc]);

  const { writeContract, data: hash, error, isPending, reset } = useWriteContract();
  const {
    isLoading: confirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  const busy = isPending || confirming;
  const label =
    mode === "claimAndLock"
      ? busy
        ? "Compounding…"
        : "Claim & lock"
      : busy
        ? "Claiming…"
        : "Claim";

  return (
    <div className={styles.wrap}>
      <button
        type="button"
        className={`${styles.btn} ${mode === "claimAndLock" ? styles.lock : styles.claim}`}
        disabled={!ready || busy}
        onClick={() => {
          reset();
          if (mode === "claimAndLock") {
            writeContract({
              address: state.deployment.feeDistributor,
              abi: abis.FeeDistributor,
              functionName: "claimAndLock",
              args: [tokenId],
            });
            return;
          }
          writeContract({
            address: state.deployment.feeDistributor,
            abi: abis.FeeDistributor,
            functionName: "claim",
            args: [tokenId, tokens],
          });
        }}
      >
        {label}
      </button>
      <p
        className={`${styles.status} ${
          error || receiptError ? styles.err : isSuccess ? styles.ok : ""
        }`}
        aria-live="polite"
      >
        {txErrorMessage(error) ||
          txErrorMessage(receiptError) ||
          (isSuccess ? "Confirmed" : "")}
      </p>
    </div>
  );
}
