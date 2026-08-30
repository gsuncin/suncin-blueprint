import { Navigate, Outlet } from "react-router-dom";

import { useAuth } from "@/hooks/useAuth";
import type { ResourceArea } from "@/types/user";

interface Props {
  resource: ResourceArea;
  capability: "view" | "manage";
}

/** Gate two: does this user's ROLE allow it?
 *
 * Fails closed. A missing or partial permissions map denies rather than
 * allows — the map is fetched over the network and "we could not load the
 * rules" must never mean "apply none of them".
 *
 * This decides what the UI offers. The backend enforces the same matrix
 * independently; this is not a security boundary on its own.
 */
export default function RequireRole({ resource, capability }: Props) {
  const { user } = useAuth();
  const allowed = Boolean(user?.permissions?.[resource]?.[capability]);

  return allowed ? <Outlet /> : <Navigate to="/" replace />;
}
