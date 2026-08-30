import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";

import RequireRole from "@/components/RequireRole";
import { makeUser, makeViewer } from "@/test/authFixtures";
import { renderWithProviders } from "@/test/renderWithProviders";
import type { User } from "@/types/user";

function renderGate(user: User | null) {
  return renderWithProviders(
    <Routes>
      <Route element={<RequireRole resource="users" capability="manage" />}>
        <Route path="/settings/users" element={<div>Users page</div>} />
      </Route>
      <Route path="/" element={<div>Dashboard</div>} />
    </Routes>,
    { route: "/settings/users", user },
  );
}

describe("RequireRole", () => {
  it("renders the route when the role allows it", () => {
    renderGate(makeUser());

    expect(screen.getByText("Users page")).toBeInTheDocument();
  });

  it("redirects when the role does not", () => {
    renderGate(makeViewer());

    expect(screen.getByText("Dashboard")).toBeInTheDocument();
  });

  it("fails closed when there is no user", () => {
    renderGate(null);

    expect(screen.getByText("Dashboard")).toBeInTheDocument();
  });

  it("fails closed when the permissions map is missing the area", () => {
    // The map arrives over the network. "We could not load the rules" must
    // never mean "apply none of them".
    renderGate(makeUser({ permissions: {} as User["permissions"] }));

    expect(screen.getByText("Dashboard")).toBeInTheDocument();
  });
});
