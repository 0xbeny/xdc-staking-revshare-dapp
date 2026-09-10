"use client";

import { DashboardNav } from "@/components/DashboardNav";
import { ProtocolCharts } from "@/components/ProtocolCharts";
import { Reveal } from "@/components/Reveal";
import { StakersTable } from "@/components/StakersTable";
import layout from "../dashboard/page.module.css";
import styles from "./page.module.css";

export default function StakersPage() {
  return (
    <div className={`shell ${layout.page}`}>
      <DashboardNav />
      <div className={layout.stack}>
        <Reveal className={layout.col} delay={0.04}>
          <h1 className={`${layout.sectionTitle} ${styles.sectionTitle}`}>Protocol overview</h1>
          <p className={`${layout.sectionLead} ${styles.sectionLead}`}>
            TVL and revenue from the indexer.
          </p>
          <ProtocolCharts />
        </Reveal>
        <Reveal className={layout.col} delay={0.1}>
          <h2 className={`${layout.sectionTitle} ${styles.sectionTitle}`}>Stakers</h2>
          <p className={`${layout.sectionLead} ${styles.sectionLead}`}>
            Open locks grouped by holder. Parent rows show total weight, veXDC, and share.
            Expand multi-veXDC wallets for each position (majority = highest weight in that
            wallet).
          </p>
          <StakersTable />
        </Reveal>
      </div>
    </div>
  );
}
