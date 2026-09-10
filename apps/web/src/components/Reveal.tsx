"use client";

import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import { gsap, prefersReducedMotion } from "@/lib/gsap";

type RevealProps = {
  children: ReactNode;
  className?: string | undefined;
  delay?: number;
  y?: number;
  style?: CSSProperties;
};

/** Fade + rise enter animation for panels and page sections. */
export function Reveal({ children, className, delay = 0, y = 18, style }: RevealProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (prefersReducedMotion()) {
      gsap.set(el, { opacity: 1, y: 0 });
      return;
    }
    const tween = gsap.fromTo(
      el,
      { opacity: 0, y },
      { opacity: 1, y: 0, duration: 0.55, delay, ease: "power2.out", clearProps: "transform" },
    );
    return () => {
      tween.kill();
    };
  }, [delay, y]);

  return (
    <div ref={ref} className={className} data-animate style={{ opacity: 0, ...style }}>
      {children}
    </div>
  );
}
