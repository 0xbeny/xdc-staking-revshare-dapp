"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import styles from "@/app/dashboard/page.module.css";

const TABS = [
  {
    href: "/dashboard",
    label: "Your positions",
    match: (p: string) => p === "/dashboard" || p.startsWith("/position"),
  },
  {
    href: "/stakers",
    label: "Protocol overview",
    match: (p: string) => p.startsWith("/stakers"),
  },
] as const;

export function DashboardNav() {
  const pathname = usePathname() ?? "/dashboard";

  return (
    <nav className={styles.tabs} aria-label="Dashboard sections">
      {TABS.map((item) => {
        const active = item.match(pathname);
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`${styles.tab} ${active ? styles.tabActive : ""}`}
            aria-current={active ? "page" : undefined}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
