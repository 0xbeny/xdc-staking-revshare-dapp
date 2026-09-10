"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef } from "react";
import { ConnectButton } from "./ConnectButton";
import { gsap, prefersReducedMotion } from "@/lib/gsap";
import styles from "./Header.module.css";

const links = [
  { href: "/dashboard", label: "Dashboard", match: (p: string) => p.startsWith("/dashboard") || p.startsWith("/position") },
  { href: "/system", label: "System", match: (p: string) => p.startsWith("/system") },
  { href: "/admin", label: "Admin", match: (p: string) => p.startsWith("/admin") },
] as const;

export function Header() {
  const pathname = usePathname() ?? "/";
  const brandRef = useRef<HTMLAnchorElement>(null);

  useEffect(() => {
    if (!brandRef.current || prefersReducedMotion()) return;
    const tween = gsap.fromTo(
      brandRef.current,
      { opacity: 0.4, y: -6 },
      { opacity: 1, y: 0, duration: 0.45, ease: "power2.out" },
    );
    return () => {
      tween.kill();
    };
  }, []);

  return (
    <header className={styles.header}>
      <div className={`shell ${styles.inner}`}>
        <Link href="/" className={styles.brand} ref={brandRef}>
          veXDC
        </Link>
        <nav className={styles.nav} aria-label="Primary">
          {links.map((link) => {
            const active = link.match(pathname);
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`${styles.link} ${active ? styles.linkActive : ""}`}
              >
                {link.label}
              </Link>
            );
          })}
          <ConnectButton />
        </nav>
      </div>
    </header>
  );
}
