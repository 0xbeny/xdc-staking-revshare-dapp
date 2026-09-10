"use client";

import { useState, type KeyboardEvent } from "react";
import { PositionsList } from "@/components/PositionsList";
import { ProtocolCharts } from "@/components/ProtocolCharts";
import { Reveal } from "@/components/Reveal";
import { StakersTable } from "@/components/StakersTable";
import styles from "./page.module.css";

type Tab = "you" | "stakers";

const TABS: { id: Tab; label: string }[] = [
  { id: "you", label: "Your positions" },
  { id: "stakers", label: "Stakers" },
];

export default function DashboardPage() {
  const [tab, setTab] = useState<Tab>("you");

  function onTabKey(e: KeyboardEvent<HTMLDivElement>) {
    if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    e.preventDefault();
    const i = TABS.findIndex((t) => t.id === tab);
    const next = e.key === "ArrowRight" ? (i + 1) % TABS.length : (i - 1 + TABS.length) % TABS.length;
    setTab(TABS[next]!.id);
  }

  return (
    <div className={`shell ${styles.page}`}>
      <div className={styles.tabs} role="tablist" aria-label="Dashboard" onKeyDown={onTabKey}>
        {TABS.map((item) => (
          <button
            key={item.id}
            type="button"
            role="tab"
            id={`tab-${item.id}`}
            aria-selected={tab === item.id}
            aria-controls={`panel-${item.id}`}
            tabIndex={tab === item.id ? 0 : -1}
            className={`${styles.tab} ${tab === item.id ? styles.tabActive : ""}`}
            onClick={() => setTab(item.id)}
          >
            {item.label}
          </button>
        ))}
      </div>

      {tab === "you" ? (
        <div className={styles.stack} id="panel-you" role="tabpanel" aria-labelledby="tab-you">
          <Reveal className={styles.col} delay={0.04}>
            <h1 className={styles.sectionTitle}>Protocol</h1>
            <p className={styles.sectionLead}>TVL and revenue from the indexer.</p>
            <ProtocolCharts />
          </Reveal>
          <Reveal className={styles.col} delay={0.1}>
            <h2 className={styles.sectionTitle}>Your positions</h2>
            <p className={styles.sectionLead}>
              Locks from the voting escrow. Claim rewards or open manage for increase, extend, and
              exit.
            </p>
            <PositionsList />
          </Reveal>
        </div>
      ) : (
        <div id="panel-stakers" role="tabpanel" aria-labelledby="tab-stakers">
          <h1 className={styles.sectionTitle}>Stakers</h1>
          <p className={styles.sectionLead}>
            Open locks grouped by holder. Combined unlock is the amount-weighted date across that
            wallet’s positions. Share is of total XDC locked.
          </p>
          <StakersTable />
        </div>
      )}
    </div>
  );
}
