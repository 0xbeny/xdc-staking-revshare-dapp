import type { ReactNode } from "react";
import styles from "./StatusPill.module.css";

type Tone = "ok" | "warn" | "danger" | "muted" | "info";

export function StatusPill({
  tone = "muted",
  children,
}: {
  tone?: Tone;
  children: ReactNode;
}) {
  const toneClass =
    tone === "ok"
      ? styles.ok
      : tone === "warn"
        ? styles.warn
        : tone === "danger"
          ? styles.danger
          : tone === "info"
            ? styles.info
            : styles.muted;

  return <span className={`${styles.pill} ${toneClass}`}>{children}</span>;
}
