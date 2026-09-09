"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "./ConnectButton";
import styles from "./Header.module.css";

export function Header() {
  const pathname = usePathname();
  const dashActive = pathname?.startsWith("/dashboard") || pathname?.startsWith("/position");

  return (
    <header className={styles.header}>
      <div className={`shell ${styles.inner}`}>
        <Link href="/" className={styles.brand}>
          veXDC
        </Link>
        <nav className={styles.nav} aria-label="Primary">
          <Link
            href="/dashboard"
            className={`${styles.link} ${dashActive ? styles.linkActive : ""}`}
          >
            Dashboard
          </Link>
          <ConnectButton />
        </nav>
      </div>
    </header>
  );
}
