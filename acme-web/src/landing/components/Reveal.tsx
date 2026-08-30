import { Box } from "@mui/material";
import { useEffect, useRef, useState, type ReactNode } from "react";

/**
 * Fades content in as it scrolls into view.
 *
 * Two things this must not do:
 *
 * 1. Hide content when the animation cannot run. If IntersectionObserver is
 *    missing, the initial state is visible, not hidden — a decorative effect
 *    must never be the reason a page is blank.
 * 2. Move anything for a visitor who asked it not to. `prefers-reduced-motion`
 *    is a stated accessibility need, and for some people motion is nausea, not
 *    polish.
 */
export default function Reveal({ children, delay = 0 }: { children: ReactNode; delay?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const prefersReducedMotion =
    typeof window !== "undefined" &&
    window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

  const [visible, setVisible] = useState(
    () => prefersReducedMotion || typeof IntersectionObserver === "undefined",
  );

  useEffect(() => {
    if (visible || !ref.current) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { rootMargin: "0px 0px -10% 0px" },
    );
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [visible]);

  return (
    <Box
      ref={ref}
      sx={{
        opacity: visible ? 1 : 0,
        transform: visible || prefersReducedMotion ? "none" : "translateY(16px)",
        transition: prefersReducedMotion
          ? "none"
          : `opacity .5s ease ${delay}ms, transform .5s ease ${delay}ms`,
      }}
    >
      {children}
    </Box>
  );
}
