import { createContext } from "react";

import type { User } from "@/types/user";

export interface AuthState {
  user: User | null;
  token: string;
  /** True until the first refresh attempt settles.
   *
   * Route guards MUST wait for this. Rendering a redirect while it is true
   * bounces every authenticated user to /login on a hard refresh, because the
   * token has not been fetched yet. */
  isAuthLoading: boolean;
  signIn: (accessToken: string) => Promise<void>;
  signOut: () => void;
}

/** Split from the provider so each module exports one kind of thing: this a
 * value, AuthProvider.tsx a component, useAuth.ts a hook.
 *
 * Mixing a component and a hook in one file breaks React Fast Refresh, which
 * then stops hot-reloading that file without saying so. The name is
 * deliberately not a case variant of AuthProvider — on a case-insensitive
 * filesystem those are the same file, and TypeScript reports it as a
 * bewildering duplicate-module error. */
export const AuthContext = createContext<AuthState | undefined>(undefined);
