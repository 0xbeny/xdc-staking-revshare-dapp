"use client";

import { IntegrateForm } from "@/components/IntegrateForm";
import styles from "../system/page.module.css";

export default function IntegratePage() {
  return (
    <div className={`shell ${styles.page}`}>
      <header className={styles.hero}>
        <p className={styles.eyebrow}>Partners</p>
        <h1 className={styles.title}>Integrate</h1>
        <p className={styles.lede}>
          Deploy an approved revenue adapter, share the address for whitelist, then skim or push
          committed fees to veXDC lockers.
        </p>
      </header>
      <IntegrateForm />
    </div>
  );
}
