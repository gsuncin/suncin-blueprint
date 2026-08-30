import { useAuth } from "@/hooks/useAuth";
import type { Entitlement } from "@/types/user";

/** Gate three: did this ACCOUNT'S PLAN buy the feature?
 *
 * Role answers who inside the account may act; this answers whether the
 * account has the feature at all. Both are enforced on the backend — this only
 * decides what the UI offers, so a stale or missing map fails closed.
 *
 * When it returns false the UI must SAY the plan does not include the feature.
 * Hiding it means the user cannot discover, let alone buy, what they are
 * missing (C-2).
 */
export function useEntitlement(entitlement: Entitlement): boolean {
  const { user } = useAuth();
  return Boolean(user?.entitlements?.[entitlement]);
}
