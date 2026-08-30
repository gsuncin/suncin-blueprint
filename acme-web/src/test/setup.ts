import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, vi } from "vitest";

// Registered explicitly because `globals: true` is off. Without it, renders
// leak between tests and a getByRole starts matching the previous test's DOM —
// which fails somewhere unrelated to the change that caused it.
afterEach(() => {
  cleanup();
});

// jsdom does not implement matchMedia, and MUI's theme plus the landing page's
// reduced-motion check both call it. Guarded because the byte-budget test runs
// in the node environment, where `window` does not exist at all.
if (typeof window !== "undefined" && !window.matchMedia) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }));
}
