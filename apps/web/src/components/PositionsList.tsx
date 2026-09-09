"use client";

import { abis } from "@vexdc/contracts";
import Link from "next/link";
import { useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
} from "wagmi";
import { ClaimButton } from "@/components/ClaimButton";
import { ManagePosition } from "@/components/ManagePosition";
import { EarningsChart } from "@/components/EarningsChart";
import { contractsReady, getContractsState } from "@/lib/contracts";
import { formatCountdown, formatDate, formatXdc } from "@/lib/format";
import styles from "./PositionsList.module.css";

const ExitKind = {
  None: 0,
  Withdraw: 1,
  Emergency: 2,
} as const;

type LockTuple = {
  amount: bigint;
  end: bigint | number;
  penaltyCapBps: bigint | number;
};

type ExitTuple = {
  requestedAt: bigint | number;
  kind: number;
  returned: bigint;
  toLockers: bigint;
  toTreasury: bigint;
  penaltyBps: bigint | number;
};

function asLock(value: unknown): LockTuple | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  if (typeof v.amount !== "bigint" && typeof v.amount !== "number") return null;
  return v as unknown as LockTuple;
}

function asExit(value: unknown): ExitTuple | null {
  if (!value || typeof value !== "object") return null;
  return value as ExitTuple;
}

export function PositionsList() {
  const { address, isConnected } = useAccount();
  const state = getContractsState();
  const ready = contractsReady(state);
  const [expanded, setExpanded] = useState<string | null>(null);

  const { data: tokenIds, isLoading: loadingIds } = useReadContract({
    address: state.deployment.votingEscrow,
    abi: abis.VotingEscrow,
    functionName: "tokensOfOwner",
    args: address ? [address] : undefined,
    query: { enabled: ready && !!address },
  });

  const { data: cooldown } = useReadContract({
    address: state.deployment.votingEscrow,
    abi: abis.VotingEscrow,
    functionName: "withdrawalCooldown",
    query: { enabled: ready },
  });

  const ids = useMemo(() => {
    if (!tokenIds) return [] as bigint[];
    return [...tokenIds] as bigint[];
  }, [tokenIds]);

  const detailContracts = useMemo(() => {
    if (!ready || ids.length === 0) return [];
    const escrow = state.deployment.votingEscrow;
    return ids.flatMap((tokenId) => [
      {
        address: escrow,
        abi: abis.VotingEscrow,
        functionName: "locked" as const,
        args: [tokenId] as const,
      },
      {
        address: escrow,
        abi: abis.VotingEscrow,
        functionName: "balanceOfNFT" as const,
        args: [tokenId] as const,
      },
      {
        address: escrow,
        abi: abis.VotingEscrow,
        functionName: "exitRequest" as const,
        args: [tokenId] as const,
      },
      {
        address: escrow,
        abi: abis.VotingEscrow,
        functionName: "closed" as const,
        args: [tokenId] as const,
      },
    ]);
  }, [ids, ready, state.deployment.votingEscrow]);

  const { data: details, isLoading: loadingDetails } = useReadContracts({
    contracts: detailContracts,
    query: { enabled: detailContracts.length > 0 },
  });

  if (!isConnected) {
    return <p className={styles.empty}>Connect a wallet to see your positions.</p>;
  }

  if (!ready) {
    return (
      <p className={styles.empty}>
        Contracts not deployed on this network — position reads are unavailable.
      </p>
    );
  }

  if (loadingIds || (ids.length > 0 && loadingDetails && !details)) {
    return <p className={styles.empty}>Loading positions…</p>;
  }

  if (ids.length === 0) {
    return (
      <p className={styles.empty}>
        No positions yet.{" "}
        <Link href="/#deposit" className={styles.link}>
          Lock XDC
        </Link>{" "}
        to mint a veNFT.
      </p>
    );
  }

  const cooldownSec = cooldown !== undefined ? Number(cooldown) : 0;

  return (
    <ul className={styles.list}>
      {ids.map((tokenId, index) => {
        const base = index * 4;
        const lock = asLock(details?.[base]?.result);
        const weight = details?.[base + 1]?.result as bigint | undefined;
        const exit = asExit(details?.[base + 2]?.result);
        const closed = Boolean(details?.[base + 3]?.result);
        const idStr = tokenId.toString();
        const isOpen = expanded === idStr;
        const exitKind = exit ? Number(exit.kind) : ExitKind.None;
        const requestedAt = exit ? Number(exit.requestedAt) : 0;
        const readyAt = requestedAt > 0 ? requestedAt + cooldownSec : 0;
        const unlock = lock ? Number(lock.end) : 0;
        const amount = lock?.amount ?? 0n;

        return (
          <li key={idStr} className={styles.item}>
            <div className={styles.row}>
              <div className={styles.meta}>
                <span className={styles.id}>#{idStr}</span>
                <span className={styles.amount}>{formatXdc(amount)} XDC</span>
                <span className={styles.detail}>
                  Unlock {unlock ? formatDate(unlock) : "—"}
                  {weight !== undefined ? ` · weight ${formatXdc(weight, 4)}` : ""}
                  {closed ? " · closed" : ""}
                </span>
                {exitKind !== ExitKind.None && (
                  <span className={styles.exitBadge}>
                    Exit pending ({exitKind === ExitKind.Emergency ? "emergency" : "withdraw"})
                    {readyAt > 0 ? ` · ${formatCountdown(readyAt)}` : ""}
                  </span>
                )}
              </div>
              <div className={styles.actions}>
                {!closed && <ClaimButton tokenId={tokenId} />}
                <button
                  type="button"
                  className={styles.manageBtn}
                  aria-expanded={isOpen}
                  onClick={() => setExpanded(isOpen ? null : idStr)}
                >
                  {isOpen ? "Hide" : "Manage"}
                </button>
                <Link href={`/position/${idStr}`} className={styles.openLink}>
                  Open
                </Link>
              </div>
            </div>
            {isOpen && (
              <div className={styles.expand}>
                <ManagePosition tokenId={tokenId} compact />
                <div className={styles.chartBlock}>
                  <h3 className={styles.chartTitle}>Earnings</h3>
                  <EarningsChart tokenId={idStr} />
                </div>
              </div>
            )}
          </li>
        );
      })}
    </ul>
  );
}
