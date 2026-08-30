import axios from "axios";

import { setToken } from "@/services/api/session";

/** Exchange the HttpOnly refresh cookie for an access token.
 *
 * Uses a bare axios call rather than the shared client: this runs before any
 * token exists, and going through the interceptor would mean a 401 here
 * triggers a refresh of the refresh.
 */
export async function refreshSession(): Promise<string | null> {
  try {
    const response = await axios.post<{ access: string }>(
      `${import.meta.env.VITE_API_URL}/auth/token/refresh/`,
      {},
      { withCredentials: true },
    );
    setToken(response.data.access);
    return response.data.access;
  } catch {
    // No cookie, expired, or blacklisted. All three mean "not signed in",
    // which is a normal state on a first visit and not an error to report.
    return null;
  }
}
