import { SystemStatus } from "@/components/SystemStatus";
import styles from "./page.module.css";

export const metadata = {
  title: "System — veXDC",
  description: "Contract registry, SystemAccess roles, and protocol health.",
};

export default function SystemPage() {
  return (
    <div className={`shell ${styles.page}`}>
      <header className={styles.hero}>
        <p className={styles.eyebrow}>Operations</p>
        <h1 className={styles.title}>System status</h1>
        <p className={styles.lede}>
          Live contract addresses, pause state, escrow parameters, and the SystemAccess role
          matrix. Read-only — admin writes live on the Admin desk.
        </p>
      </header>
      <SystemStatus />
    </div>
  );
}
