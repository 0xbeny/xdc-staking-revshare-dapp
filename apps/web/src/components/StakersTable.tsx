"use client";

import { useQueries, useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { AddressLink } from "@/components/AddressLink";
import { estimateLockWeight, getConfiguredChainId } from "@/lib/contracts";
import { formatDate, formatShareBps, formatXdc } from "@/lib/format";
import {
  fetchOwnerPositions,
  fetchProtocolStakers,
  type IndexerPosition,
  type ProtocolStaker,
  type ProtocolStakerPosition,
} from "@/lib/indexer";
import styles from "./StakersTable.module.css";

const PAGE_SIZE = 50;

function asWei(raw: string | undefined | null): bigint {
  if (raw == null || raw === "") return 0n;
  try {
    const n = BigInt(raw);
    return n < 0n ? 0n : n;
  } catch {
    return 0n;
  }
}

/**
 * Prefer API weight → sum of position weights → estimate from amount+unlock.
 * Older prod indexers omit `weight` / `positions`; never leave the UI blank.
 */
function resolveStakerWeight(
  row: ProtocolStaker,
  positions: ProtocolStakerPosition[],
  nowSec: number,
): bigint {
  const api = asWei(row.weight);
  if (api > 0n) return api;

  const fromPositions = positions.reduce((sum, p) => sum + asWei(p.weight), 0n);
  if (fromPositions > 0n) return fromPositions;

  const amount = asWei(row.amount);
  if (amount === 0n) return 0n;
  // Single lock or amount-weighted average unlock from older API.
  if (row.unlockTime > nowSec) {
    return estimateLockWeight(amount, row.unlockTime, nowSec);
  }
  return 0n;
}

function buildPositions(
  row: ProtocolStaker,
  fetched: IndexerPosition[] | undefined,
  nowSec: number,
  poolWeight: bigint,
): ProtocolStakerPosition[] {
  const apiPositions = row.positions;
  const raw =
    apiPositions && apiPositions.length > 0
      ? apiPositions.map((p) => {
          const amount = asWei(p.amount);
          const apiWeight = asWei(p.weight);
          return {
            tokenId: p.tokenId,
            amount: p.amount,
            unlockTime: p.unlockTime,
            weight:
              apiWeight > 0n
                ? apiWeight
                : estimateLockWeight(amount, p.unlockTime, nowSec),
            majority: p.majority,
          };
        })
      : (fetched ?? [])
          .filter((p) => !p.closed && asWei(p.amount) > 0n)
          .map((p) => ({
            tokenId: p.tokenId,
            amount: p.amount,
            unlockTime: p.unlockTime,
            weight: estimateLockWeight(asWei(p.amount), p.unlockTime, nowSec),
            majority: undefined as boolean | undefined,
          }));

  raw.sort((a, b) => {
    const d = b.weight - a.weight;
    if (d > 0n) return 1;
    if (d < 0n) return -1;
    return a.tokenId.localeCompare(b.tokenId);
  });

  return raw.map((p, i) => ({
    tokenId: p.tokenId,
    amount: p.amount,
    weight: p.weight.toString(10),
    unlockTime: p.unlockTime,
    shareBps: poolWeight === 0n ? 0 : Number((p.weight * 10_000n) / poolWeight),
    majority: p.majority ?? (raw.length > 1 && i === 0),
  }));
}

function StakerAccordion({
  row,
  chainId,
  mine,
  rank,
  isTopShare,
  poolWeight,
  nowSec,
  fetchedPositions,
  childrenLoading,
}: {
  row: ProtocolStaker;
  chainId: number;
  mine: boolean;
  rank: number;
  isTopShare: boolean;
  poolWeight: bigint;
  nowSec: number;
  fetchedPositions?: IndexerPosition[] | undefined;
  childrenLoading?: boolean | undefined;
}) {
  const positions = useMemo(
    () => buildPositions(row, fetchedPositions, nowSec, poolWeight),
    [row, fetchedPositions, nowSec, poolWeight],
  );
  const multi = row.positionCount > 1 || positions.length > 1;
  const [open, setOpen] = useState(false);
  const weight = useMemo(
    () => resolveStakerWeight(row, positions, nowSec),
    [row, positions, nowSec],
  );
  // Multi-holder still loading and no unlock-based estimate yet.
  const weightPending =
    Boolean(childrenLoading) &&
    positions.length === 0 &&
    asWei(row.weight) === 0n &&
    asWei(row.amount) > 0n &&
    !(row.unlockTime > nowSec);
  const shareBps =
    poolWeight === 0n ? row.shareBps : Number((weight * 10_000n) / poolWeight);

  const lockLabel = multi
    ? `${positions.length > 0 ? positions.length : row.positionCount} veXDC`
    : "1 veXDC";

  return (
    <article className={`${styles.item} ${mine ? styles.you : ""} ${open ? styles.itemOpen : ""}`}>
      <button
        type="button"
        className={styles.parentBtn}
        aria-expanded={multi ? open : undefined}
        aria-controls={multi ? `staker-${row.owner}-nfts` : undefined}
        disabled={!multi}
        onClick={() => {
          if (multi) setOpen((v) => !v);
        }}
      >
        <span className={styles.parentMain}>
          <span className={styles.identity}>
            <span className={styles.idRow}>
              <span className={styles.rank} aria-label={`Rank ${rank}`}>
                #{rank}
              </span>
              <span
                className={styles.addrWrap}
                onClick={(e) => e.stopPropagation()}
                onKeyDown={(e) => e.stopPropagation()}
              >
                <AddressLink address={row.owner} chainId={chainId} />
              </span>
            </span>
            <span className={styles.meta}>
              {mine ? <span className={styles.youTag}>You</span> : null}
              {isTopShare ? <span className={styles.majority}>Majority</span> : null}
              <span className={styles.locks}>{lockLabel}</span>
            </span>
          </span>
        </span>
        <span className={styles.metrics}>
          <span className={styles.metric}>
            <span className={`${styles.metricLabel} ${styles.brandCase}`}>veXDC</span>
            <span className={styles.metricValue}>
              {weightPending ? "…" : formatXdc(weight)}
            </span>
          </span>
          <span className={styles.metric}>
            <span className={styles.metricLabel}>XDC Locked</span>
            <span className={styles.metricValue}>{formatXdc(asWei(row.amount))}</span>
          </span>
          <span className={styles.metric}>
            <span className={styles.metricLabel}>Share</span>
            <span className={styles.metricValue}>{formatShareBps(shareBps)}</span>
          </span>
        </span>
        <span className={`${styles.chevron} ${open && multi ? styles.chevronOpen : ""}`} aria-hidden>
          {multi ? (
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <path
                d="M3 4.5L6 7.5L9 4.5"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          ) : (
            <span className={styles.dot} />
          )}
        </span>
      </button>

      <div
        className={styles.panel}
        data-open={open && multi ? "true" : "false"}
        id={`staker-${row.owner}-nfts`}
      >
        <div className={styles.panelInner}>
          {positions.length === 0 ? (
            <p className={styles.panelStatus}>
              {childrenLoading ? "Loading positions…" : "No open positions found."}
            </p>
          ) : (
            <>
              <div className={styles.childHead}>
                <span>Position</span>
                <span>Weight</span>
                <span className={styles.brandCase}>veXDC</span>
                <span>Unlock</span>
                <span>Share</span>
                <span>Open</span>
              </div>
              <ul className={styles.childList}>
                {positions.map((pos) => (
                  <li key={pos.tokenId} className={styles.child}>
                    <div className={styles.childPos}>
                      <Link href={`/position/${pos.tokenId}`} className={styles.nftLink}>
                        #{pos.tokenId}
                      </Link>
                      {pos.majority ? <span className={styles.majority}>Majority</span> : null}
                    </div>
                    <span className={styles.num}>{formatXdc(asWei(pos.weight))}</span>
                    <span className={styles.num}>{formatXdc(asWei(pos.amount))}</span>
                    <time dateTime={new Date(pos.unlockTime * 1000).toISOString()}>
                      {formatDate(pos.unlockTime)}
                    </time>
                    <span className={styles.num}>{formatShareBps(pos.shareBps)}</span>
                    <Link href={`/position/${pos.tokenId}`} className={styles.openLink}>
                      Open
                    </Link>
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      </div>
    </article>
  );
}

export function StakersTable() {
  const chainId = getConfiguredChainId();
  const { address } = useAccount();
  const you = address?.toLowerCase();
  const nowSec = Math.floor(Date.now() / 1000);

  const query = useQuery({
    queryKey: ["protocol-stakers"],
    queryFn: fetchProtocolStakers,
    staleTime: 30_000,
  });

  const stakers = query.data?.stakers ?? [];
  const [page, setPage] = useState(1);

  useEffect(() => {
    setPage(1);
  }, [stakers.length]);

  const ownersNeedingFetch = useMemo(
    () =>
      stakers
        .filter((s) => s.positionCount > 1 && (!s.positions || s.positions.length === 0))
        .map((s) => s.owner),
    [stakers],
  );

  const positionQueries = useQueries({
    queries: ownersNeedingFetch.map((owner) => ({
      queryKey: ["owner-positions", owner],
      queryFn: () => fetchOwnerPositions(owner),
      staleTime: 30_000,
      enabled: Boolean(query.data) && ownersNeedingFetch.length > 0,
    })),
  });

  const fetchedByOwner = useMemo(() => {
    const map = new Map<string, IndexerPosition[]>();
    ownersNeedingFetch.forEach((owner, i) => {
      const data = positionQueries[i]?.data;
      if (data) map.set(owner, data);
    });
    return map;
  }, [ownersNeedingFetch, positionQueries]);

  const loadingByOwner = useMemo(() => {
    const map = new Map<string, boolean>();
    ownersNeedingFetch.forEach((owner, i) => {
      const q = positionQueries[i];
      map.set(owner, Boolean(q?.isLoading || q?.isFetching) && !q?.data);
    });
    return map;
  }, [ownersNeedingFetch, positionQueries]);

  if (query.isLoading) {
    return <p className={styles.empty}>Loading stakers…</p>;
  }
  if (query.isError || !query.data) {
    return <p className={styles.empty}>Could not reach indexer.</p>;
  }

  const payload = query.data;
  if (stakers.length === 0) {
    return <p className={styles.empty}>No open locks indexed yet.</p>;
  }

  const total = asWei(payload.totalAmount);

  // Pool weight: prefer API, else resolve per row (API / positions / amount+unlock).
  let poolWeight = asWei(payload.totalWeight);
  if (poolWeight === 0n) {
    for (const s of stakers) {
      const fetched = fetchedByOwner.get(s.owner);
      const pos = buildPositions(s, fetched, nowSec, 1n);
      poolWeight += resolveStakerWeight(s, pos, nowSec);
    }
  }

  const loadingChildren = ownersNeedingFetch.some((owner) => loadingByOwner.get(owner));

  // Same share as parent row (weight-based when pool weight is known).
  const ranked = stakers
    .map((row) => {
      const fetched = fetchedByOwner.get(row.owner);
      const positions = buildPositions(row, fetched, nowSec, poolWeight);
      const weight = resolveStakerWeight(row, positions, nowSec);
      const shareBps =
        poolWeight === 0n ? row.shareBps : Number((weight * 10_000n) / poolWeight);
      return { row, shareBps };
    })
    .sort((a, b) => {
      if (b.shareBps !== a.shareBps) return b.shareBps - a.shareBps;
      return a.row.owner.localeCompare(b.row.owner);
    });

  const pageCount = Math.max(1, Math.ceil(ranked.length / PAGE_SIZE));
  const safePage = Math.min(Math.max(1, page), pageCount);
  const rangeStart = (safePage - 1) * PAGE_SIZE;
  const pageRows = ranked.slice(rangeStart, rangeStart + PAGE_SIZE);
  const rangeEnd = rangeStart + pageRows.length;
  const showPager = ranked.length > PAGE_SIZE;

  return (
    <div className={styles.wrap}>
      <div className={styles.summaryBar}>
        <p className={styles.summary}>
          <strong>{payload.stakerCount ?? stakers.length}</strong> holders
          <span className={styles.sep}>·</span>
          <strong>{formatXdc(total)}</strong> XDC
          <span className={styles.sep}>·</span>
          weight <strong>{formatXdc(poolWeight)}</strong>
          <span className={styles.sep}>·</span>
          <strong>{payload.positionCount ?? stakers.length}</strong> positions
        </p>
        {loadingChildren ? <span className={styles.loadingHint}>Loading positions…</span> : null}
      </div>

      <div className={styles.list} role="list">
        {pageRows.map(({ row }, index) => {
          const fetched = fetchedByOwner.get(row.owner);
          const rank = rangeStart + index + 1;
          return (
            <StakerAccordion
              key={row.owner}
              row={row}
              chainId={chainId}
              mine={you !== undefined && row.owner === you}
              rank={rank}
              isTopShare={rank === 1}
              poolWeight={poolWeight}
              nowSec={nowSec}
              fetchedPositions={fetched}
              childrenLoading={loadingByOwner.get(row.owner) ?? false}
            />
          );
        })}
      </div>

      {showPager ? (
        <nav className={styles.pager} aria-label="Stakers pagination">
          <p className={styles.pagerInfo}>
            Showing {rangeStart + 1}–{rangeEnd} of {ranked.length}
            <span className={styles.sep}>·</span>
            {safePage} / {pageCount}
          </p>
          <div className={styles.pagerBtns}>
            <button
              type="button"
              className={styles.pagerBtn}
              disabled={safePage <= 1}
              onClick={() => setPage((p) => Math.max(1, p - 1))}
            >
              Previous
            </button>
            <button
              type="button"
              className={styles.pagerBtn}
              disabled={safePage >= pageCount}
              onClick={() => setPage((p) => Math.min(pageCount, p + 1))}
            >
              Next
            </button>
          </div>
        </nav>
      ) : null}
    </div>
  );
}
