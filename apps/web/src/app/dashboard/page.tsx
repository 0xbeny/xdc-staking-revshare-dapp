import { PositionsList } from "@/components/PositionsList";
import { ProtocolCharts } from "@/components/ProtocolCharts";
import styles from "./page.module.css";

export default function DashboardPage() {
  return (
    <div className={`shell ${styles.page}`}>
      <div className={styles.grid}>
        <div className={styles.col}>
          <div>
            <h1 className={styles.sectionTitle}>Your positions</h1>
            <p className={styles.sectionLead}>
              Locks from the voting escrow. Claim rewards or open manage for increase, extend, and
              exit.
            </p>
            <PositionsList />
          </div>
        </div>
        <div className={styles.col}>
          <div>
            <h2 className={styles.sectionTitle}>Protocol</h2>
            <p className={styles.sectionLead}>TVL and revenue from the indexer.</p>
            <ProtocolCharts />
          </div>
        </div>
      </div>
    </div>
  );
}
