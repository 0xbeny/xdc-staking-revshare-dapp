"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { ManagePosition } from "@/components/ManagePosition";
import { EarningsChart } from "@/components/EarningsChart";
import styles from "./page.module.css";

export default function PositionPage() {
  const params = useParams<{ tokenId: string }>();
  const raw = params.tokenId ?? "";
  let tokenId: bigint | null = null;
  try {
    if (/^\d+$/.test(raw)) tokenId = BigInt(raw);
  } catch {
    tokenId = null;
  }

  if (tokenId === null) {
    return (
      <div className={`shell ${styles.page}`}>
        <p className={styles.error}>Invalid position id.</p>
        <Link href="/dashboard" className={styles.back}>
          ← Dashboard
        </Link>
      </div>
    );
  }

  return (
    <div className={`shell ${styles.page}`}>
      <Link href="/dashboard" className={styles.back}>
        ← Dashboard
      </Link>
      <h1 className={styles.title}>Position #{tokenId.toString()}</h1>
      <div className={styles.layout}>
        <ManagePosition tokenId={tokenId} />
        <section className={styles.earnings} aria-labelledby="earnings-title">
          <h2 id="earnings-title" className={styles.sub}>
            Earnings
          </h2>
          <EarningsChart tokenId={tokenId.toString()} />
        </section>
      </div>
    </div>
  );
}
