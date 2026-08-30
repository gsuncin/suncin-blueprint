import { describe, expect, it } from "vitest";

import {
  LANDING_HEADLINE,
  NOSCRIPT_FALLBACK_STYLESHEET,
  renderNoscriptFallbackHtml,
} from "@/landing/noscriptFallback";

describe("noscript fallback", () => {
  it("says what the page is about", () => {
    expect(renderNoscriptFallbackHtml()).toContain(LANDING_HEADLINE);
  });

  it("offers a way in that does not need JavaScript", () => {
    expect(renderNoscriptFallbackHtml()).toContain('href="/login"');
  });

  it("hides the empty React root, so the page is not blank above the fallback", () => {
    expect(NOSCRIPT_FALLBACK_STYLESHEET).toContain("#root");
    expect(NOSCRIPT_FALLBACK_STYLESHEET).toContain("display: none");
  });
});
