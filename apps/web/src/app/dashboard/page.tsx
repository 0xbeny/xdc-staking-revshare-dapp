"use client";

import { DashboardNav } from "@/components/DashboardNav";
import { PositionsList } from "@/components/PositionsList";
import { Reveal } from "@/components/Reveal";
import styles from "./page.module.css";

export default function DashboardPage() {
  return (
    <div className={`shell ${styles.page}`}>
      <DashboardNav />
      <Reveal className={styles.col} delay={0.04}>
        <h1 className={styles.sectionTitle}>Your positions</h1>
        <p className={styles.sectionLead}>
          Locks from the voting escrow. Claim rewards or open manage for increase, extend, and exit.
        </p>
        <PositionsList />
      </Reveal>
    </div>
  );
}
