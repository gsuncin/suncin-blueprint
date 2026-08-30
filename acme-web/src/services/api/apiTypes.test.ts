import { describe, expect, it } from "vitest";

import { normalizeApiError } from "@/services/api/apiTypes";

describe("normalizeApiError", () => {
  it("reads a DRF permission denial from detail", () => {
    const error = normalizeApiError({
      response: { status: 403, data: { detail: "Your role does not allow this action." } },
    });

    expect(error.status).toBe(403);
    expect(error.message).toBe("Your role does not allow this action.");
  });

  it("keeps the plan-denial code so the UI can offer an upgrade", () => {
    // Losing this code turns "your plan does not include this" into
    // "forbidden", which sends the user to their admin instead of to pricing.
    const error = normalizeApiError({
      response: { status: 403, data: { detail: "Not in plan", code: "PLAN_NOT_ENTITLED" } },
    });

    expect(error.code).toBe("PLAN_NOT_ENTITLED");
  });

  it("reads a serializer field error and names the field", () => {
    const error = normalizeApiError({
      response: { status: 400, data: { recipient: ["This field is required."] } },
    });

    expect(error.message).toBe("recipient: This field is required.");
  });

  it("reads non_field_errors", () => {
    const error = normalizeApiError({
      response: { status: 400, data: { non_field_errors: ["Nope."] } },
    });

    expect(error.message).toBe("Nope.");
  });

  it("falls back to the axios message when there is no body", () => {
    expect(normalizeApiError({ message: "Network Error" }).message).toBe("Network Error");
  });

  it("never returns undefined for a message", () => {
    // Whatever went wrong, something has to be renderable.
    expect(normalizeApiError({}).message).toBeTruthy();
  });
});
