import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import EntitlementGate from "@/components/EntitlementGate";
import { makeUnentitled, makeUser } from "@/test/authFixtures";
import { renderWithProviders } from "@/test/renderWithProviders";
import type { User } from "@/types/user";

const feature = (
  <EntitlementGate entitlement="example_jobs" featureName="Outbound jobs">
    <div>The feature</div>
  </EntitlementGate>
);

describe("EntitlementGate", () => {
  it("renders the feature when the plan includes it", () => {
    renderWithProviders(feature, { user: makeUser() });

    expect(screen.getByText("The feature")).toBeInTheDocument();
  });

  it("tells the user their plan lacks it instead of hiding it", () => {
    // A feature the user cannot see is a feature they cannot buy, and this is
    // a different problem from "you have no permission" (C-2).
    renderWithProviders(feature, { user: makeUnentitled() });

    expect(screen.queryByText("The feature")).not.toBeInTheDocument();
    expect(screen.getByText(/is not in your plan/i)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /see plans/i })).toBeInTheDocument();
  });

  it("fails closed when the entitlements map is missing", () => {
    renderWithProviders(feature, {
      user: makeUser({ entitlements: {} as User["entitlements"] }),
    });

    expect(screen.queryByText("The feature")).not.toBeInTheDocument();
  });
});
