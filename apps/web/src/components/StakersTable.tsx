"use client";

import { useQuery } from "@tanstack/react-query";
import { useAccount } from "wagmi";
import { AddressLink } from "@/components/AddressLink";
import { getConfiguredChainId } from "@/lib/contracts";
import { formatDate, formatShareBps, formatXdc } from "@/lib/format";
import { fetchProtocolStakers } from "@/lib/indexer";
import styles from "./StakersTable.module.css";

export function StakersTable() {
  const chainId = getConfiguredChainId();
  const { address } = useAccount();
  const you = address?.toLowerCase();
  const query = useQuery({
    queryKey: ["protocol-stakers"],
    queryFn: fetchProtocolStakers,
    staleTime: 30_000,
  });

  if (query.isLoading) {
    return <p className={styles.empty}>Loading stakers…</p>;
  }
  if (query.isError || query.data === null) {
    return <p className={styles.empty}>Could not reach indexer.</p>;
  }

  const payload = query.data;
  const rows = payload?.stakers ?? [];
  if (rows.length === 0) {
    return <p className={styles.empty}>No open locks indexed yet.</p>;
  }

  const total = BigInt(payload?.totalAmount ?? "0");

  return (
    <div className={styles.wrap}>
      <p className={styles.summary}>
        {payload?.stakerCount ?? rows.length} holders · {formatXdc(total)} XDC locked ·{" "}
        {payload?.positionCount ?? rows.length} positions
      </p>
      <div className={styles.scroll}>
        <table className={styles.table}>
          <thead>
            <tr>
              <th scope="col">Holder</th>
              <th scope="col">XDC staked</th>
              <th scope="col">Combined unlock</th>
              <th scope="col">Share</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => {
              const mine = you !== undefined && row.owner === you;
              return (
                <tr key={row.owner} className={mine ? styles.you : undefined}>
                  <th scope="row">
                    <AddressLink address={row.owner} chainId={chainId} />
                    {row.positionCount > 1 ? (
                      <span className={styles.locks}>
                        {row.positionCount} locks
                      </span>
                    ) : null}
                    {mine ? <span className={styles.youTag}>You</span> : null}
                  </th>
                  <td className={styles.num}>{formatXdc(BigInt(row.amount))} XDC</td>
                  <td>
                    <time dateTime={new Date(row.unlockTime * 1000).toISOString()}>
                      {formatDate(row.unlockTime)}
                    </time>
                  </td>
                  <td className={styles.num}>{formatShareBps(row.shareBps)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <ul className={styles.cards} aria-label="Stakers">
        {rows.map((row) => {
          const mine = you !== undefined && row.owner === you;
          return (
            <li key={row.owner} className={`${styles.card} ${mine ? styles.you : ""}`}>
              <div className={styles.cardHead}>
                <AddressLink address={row.owner} chainId={chainId} />
                {mine ? <span className={styles.youTag}>You</span> : null}
              </div>
              <dl className={styles.dl}>
                <div>
                  <dt>XDC staked</dt>
                  <dd>{formatXdc(BigInt(row.amount))} XDC</dd>
                </div>
                <div>
                  <dt>Combined unlock</dt>
                  <dd>{formatDate(row.unlockTime)}</dd>
                </div>
                <div>
                  <dt>Share</dt>
                  <dd>{formatShareBps(row.shareBps)}</dd>
                </div>
              </dl>
              {row.positionCount > 1 ? (
                <p className={styles.locks}>{row.positionCount} locks · amount-weighted unlock</p>
              ) : null}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
