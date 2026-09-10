"use client";

import { PositionsList } from "@/components/PositionsList";
import { ProtocolCharts } from "@/components/ProtocolCharts";
import { Reveal } from "@/components/Reveal";
import styles from "./page.module.css";

export default function DashboardPage() {
  return (
    <div className={`shell ${styles.page}`}>
      <div className={styles.grid}>
        <Reveal className={styles.col} delay={0.04}>
          <h1 className={styles.sectionTitle}>Your positions</h1>
          <p className={styles.sectionLead}>
            Locks from the voting escrow. Claim rewards or open manage for increase, extend, and
            exit.
          </p>
          <PositionsList />
        </Reveal>
        <Reveal className={styles.col} delay={0.12}>
          <h2 className={styles.sectionTitle}>Protocol</h2>
          <p className={styles.sectionLead}>TVL and revenue from the indexer.</p>
          <ProtocolCharts />
        </Reveal>
      </div>
    </div>
  );
}
