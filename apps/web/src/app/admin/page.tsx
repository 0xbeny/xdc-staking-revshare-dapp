"use client";

import { AdminActions } from "@/components/AdminActions";
import styles from "../system/page.module.css";

export default function AdminPage() {
  return (
    <div className={`shell ${styles.page}`}>
      <header className={styles.hero}>
        <p className={styles.eyebrow}>Governance</p>
        <h1 className={styles.title}>Admin desk</h1>
        <p className={styles.lede}>
          Pause, tune escrow clamps, manage adapters, and grant or revoke SystemAccess roles.
          Cards unlock only when your connected wallet holds the required authority.
        </p>
      </header>
      <AdminActions />
    </div>
  );
}
