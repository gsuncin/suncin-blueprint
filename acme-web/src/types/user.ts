/** Mirrors acme-bff users/permissions.py and accounts/entitlements.py.
 *
 * Both maps arrive on the /api/auth/logged/ payload rather than being derived
 * here. The backend is the only place the rules live; this file is the shape
 * they arrive in, and nothing more.
 */

export type UserRole = "OWNER" | "ADMIN" | "MEMBER" | "VIEWER";

export type ResourceArea = "account" | "users" | "example" | "audit";

export interface ResourceCapabilities {
  view: boolean;
  manage: boolean;
}

export type PermissionsMap = Record<ResourceArea, ResourceCapabilities>;

/** Plan-level, NOT role-level. See CONSTITUTION C-2 for why they are separate. */
export type Entitlement = "example_jobs" | "bulk_export";

export type EntitlementsMap = Record<Entitlement, boolean>;

export interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  role: UserRole;
  account: string | null;
  is_active: boolean;
  permissions: PermissionsMap;
  entitlements: EntitlementsMap;
}

export const USER_ROLE_LABELS: Record<UserRole, string> = {
  OWNER: "Owner",
  ADMIN: "Admin",
  MEMBER: "Member",
  VIEWER: "Viewer",
};
