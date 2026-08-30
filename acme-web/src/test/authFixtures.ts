import type { EntitlementsMap, PermissionsMap, User } from "@/types/user";

const FULL: PermissionsMap = {
  account: { view: true, manage: true },
  users: { view: true, manage: true },
  example: { view: true, manage: true },
  audit: { view: true, manage: true },
};

const READ_ONLY: PermissionsMap = {
  account: { view: false, manage: false },
  users: { view: false, manage: false },
  example: { view: true, manage: false },
  audit: { view: false, manage: false },
};

const ALL_ENTITLED: EntitlementsMap = { example_jobs: true, bulk_export: true };
const NONE_ENTITLED: EntitlementsMap = { example_jobs: false, bulk_export: false };

export function makeUser(overrides: Partial<User> = {}): User {
  return {
    id: "user-1",
    email: "ada@acme.test",
    first_name: "Ada",
    last_name: "Lovelace",
    role: "OWNER",
    account: "acct-1",
    is_active: true,
    permissions: FULL,
    entitlements: ALL_ENTITLED,
    ...overrides,
  };
}

export const makeViewer = () => makeUser({ role: "VIEWER", permissions: READ_ONLY });
export const makeUnentitled = () => makeUser({ entitlements: NONE_ENTITLED });
