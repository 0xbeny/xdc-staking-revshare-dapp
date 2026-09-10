"use client";

import { useEffect, useRef } from "react";
import { DepositForm } from "@/components/DepositForm";
import { gsap, prefersReducedMotion } from "@/lib/gsap";
import styles from "./page.module.css";

export default function HomePage() {
  const heroRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const root = heroRef.current;
    if (!root || prefersReducedMotion()) return;
    const ctx = gsap.context(() => {
      gsap.fromTo(
        `.${styles.widget}`,
        { opacity: 0, y: 16 },
        { opacity: 1, y: 0, duration: 0.5, ease: "power3.out" },
      );
    }, root);
    return () => ctx.revert();
  }, []);

  return (
    <section className={styles.hero} aria-label="Stake XDC" ref={heroRef}>
      <div className={styles.heroGlow} aria-hidden />
      <div className={styles.widget}>
        <DepositForm />
      </div>
    </section>
  );
}
