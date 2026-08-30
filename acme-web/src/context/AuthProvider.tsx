import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";

import { AuthContext } from "@/context/authState";
import { clearSession, getToken, setToken } from "@/services/api/session";
import { getLoggedUser } from "@/services/auth/getLoggedUser";
import { refreshSession } from "@/services/auth/refreshSession";
import type { User } from "@/types/user";

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [token, setTokenState] = useState<string>(getToken());
  const [isAuthLoading, setIsAuthLoading] = useState(true);

  const signIn = useCallback(async (accessToken: string) => {
    setToken(accessToken);
    setTokenState(accessToken);
    setUser(await getLoggedUser());
  }, []);

  const signOut = useCallback(() => {
    clearSession();
    setTokenState("");
    setUser(null);
  }, []);

  useEffect(() => {
    let cancelled = false;

    // The access token only lives in memory, so a reload always starts with
    // none. The HttpOnly cookie is what carries the session across it.
    (async () => {
      const accessToken = await refreshSession();
      if (cancelled) return;

      if (!accessToken) {
        setIsAuthLoading(false);
        return;
      }

      try {
        const loaded = await getLoggedUser();
        if (cancelled) return;
        setTokenState(accessToken);
        setUser(loaded);
      } catch {
        // A valid token whose user cannot be loaded is not a usable session.
        clearSession();
      } finally {
        if (!cancelled) setIsAuthLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  const value = useMemo(
    () => ({ user, token, isAuthLoading, signIn, signOut }),
    [user, token, isAuthLoading, signIn, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
