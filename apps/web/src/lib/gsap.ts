"use client";

import gsap from "gsap";

export function prefersReducedMotion(): boolean {
  if (typeof window === "undefined") return false;
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Run a GSAP timeline only when motion is allowed; otherwise apply final state instantly. */
export function safeGsap(run: (g: typeof gsap) => gsap.core.Timeline | gsap.core.Tween | void): void {
  if (prefersReducedMotion()) {
    gsap.set("[data-animate]", { clearProps: "all", opacity: 1, y: 0, scale: 1 });
    return;
  }
  run(gsap);
}

export { gsap };
