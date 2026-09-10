"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useId, useRef, useState } from "react";
import { ConnectButton } from "./ConnectButton";
import { gsap, prefersReducedMotion } from "@/lib/gsap";
import styles from "./Header.module.css";

const links = [
  { href: "/", label: "Stake", match: (p: string) => p === "/" },
  {
    href: "/dashboard",
    label: "Dashboard",
    match: (p: string) => p.startsWith("/dashboard") || p.startsWith("/stakers") || p.startsWith("/position"),
  },
  { href: "/integrate", label: "Integrate", match: (p: string) => p.startsWith("/integrate") },
  { href: "/system", label: "System", match: (p: string) => p.startsWith("/system") },
  { href: "/admin", label: "Admin", match: (p: string) => p.startsWith("/admin") },
] as const;

export function Header() {
  const pathname = usePathname() ?? "/";
  const brandRef = useRef<HTMLAnchorElement>(null);
  const menuId = useId();
  const [menuOpen, setMenuOpen] = useState(false);

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

  useEffect(() => {
    setMenuOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!menuOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setMenuOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    const mq = window.matchMedia("(min-width: 768px)");
    const onChange = () => {
      if (mq.matches) setMenuOpen(false);
    };
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [menuOpen]);

  return (
    <header className={styles.header}>
      <div className={`shell ${styles.inner}`}>
        <Link href="/" className={styles.brand} ref={brandRef}>
          veXDC
        </Link>

        <div className={styles.toolbar}>
          <button
            type="button"
            className={styles.menuBtn}
            aria-expanded={menuOpen}
            aria-controls={menuId}
            aria-label={menuOpen ? "Close menu" : "Open menu"}
            onClick={() => setMenuOpen((v) => !v)}
          >
            <span className={styles.menuIcon} aria-hidden>
              <span className={menuOpen ? styles.barOpenTop : styles.bar} />
              <span className={menuOpen ? styles.barOpenMid : styles.bar} />
              <span className={menuOpen ? styles.barOpenBot : styles.bar} />
            </span>
          </button>

          <nav
            id={menuId}
            className={`${styles.nav} ${menuOpen ? styles.navOpen : ""}`}
            aria-label="Primary"
          >
            {links.map((link) => {
              const active = link.match(pathname);
              return (
                <Link
                  key={link.href}
                  href={link.href}
                  className={`${styles.link} ${active ? styles.linkActive : ""}`}
                  onClick={() => setMenuOpen(false)}
                >
                  {link.label}
                </Link>
              );
            })}
          </nav>

          <div className={styles.connect}>
            <ConnectButton />
          </div>
        </div>
      </div>

      {menuOpen ? (
        <button
          type="button"
          className={styles.backdrop}
          aria-label="Close menu"
          onClick={() => setMenuOpen(false)}
        />
      ) : null}
    </header>
  );
}
