import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import Reveal from "@/landing/components/Reveal";

const originalMatchMedia = window.matchMedia;
const originalObserver = globalThis.IntersectionObserver;

afterEach(() => {
  window.matchMedia = originalMatchMedia;
  globalThis.IntersectionObserver = originalObserver;
});

function setReducedMotion(reduce: boolean) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: reduce && query.includes("prefers-reduced-motion"),
    media: query,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
    onchange: null,
  })) as typeof window.matchMedia;
}

describe("Reveal", () => {
  it("shows content immediately and does not move it when motion is reduced", () => {
    setReducedMotion(true);

    render(<Reveal><p>Visible copy</p></Reveal>);

    const wrapper = screen.getByText("Visible copy").parentElement!;
    expect(wrapper).toHaveStyle({ opacity: "1" });
    expect(wrapper).toHaveStyle({ transform: "none" });
  });

  it("still renders content when IntersectionObserver is unavailable", () => {
    // A decorative effect must never be the reason a page is blank.
    setReducedMotion(false);
    // @ts-expect-error deliberately removing the API to model an old browser
    delete globalThis.IntersectionObserver;

    render(<Reveal><p>Visible copy</p></Reveal>);

    expect(screen.getByText("Visible copy").parentElement).toHaveStyle({ opacity: "1" });
  });
});
