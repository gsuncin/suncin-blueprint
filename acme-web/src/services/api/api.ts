import axios, { type AxiosError, type InternalAxiosRequestConfig } from "axios";

import { normalizeApiError } from "@/services/api/apiTypes";
import { clearSession, getToken, setToken } from "@/services/api/session";

const baseURL = import.meta.env.VITE_API_URL;
if (!baseURL) {
  // Fail at module load, not at the first request. A missing base URL produces
  // requests to the wrong origin that fail as CORS errors, which sends you
  // debugging the backend.
  throw new Error("VITE_API_URL is not defined");
}

export const api = axios.create({
  baseURL,
  timeout: 60_000,
  // Required for the HttpOnly refresh cookie to travel.
  withCredentials: true,
});

/** A second client with no interceptors.
 *
 * The refresh call must never be retried by the refresh logic — that is an
 * infinite loop, and it is the classic way to DDoS your own login endpoint.
 */
const refreshClient = axios.create({ baseURL, timeout: 60_000, withCredentials: true });

const isAuthEndpoint = (url = "") => url.includes("auth/token");

/** One in-flight refresh, shared.
 *
 * A page that fires six requests on mount gets six 401s at once. Without this,
 * each one starts its own refresh; the token rotates six times and five of the
 * six replays fail with a token that was just invalidated.
 */
let refreshRequest: Promise<string> | null = null;

function refreshAccessToken(): Promise<string> {
  refreshRequest ??= refreshClient
    .post<{ access: string }>("/auth/token/refresh/", {})
    .then((response) => {
      setToken(response.data.access);
      return response.data.access;
    })
    .finally(() => {
      refreshRequest = null;
    });
  return refreshRequest;
}

export function redirectToLogin(): void {
  clearSession();
  if (window.location.pathname === "/login") return;
  const redirect = encodeURIComponent(window.location.pathname + window.location.search);
  window.location.href = `/login?redirect=${redirect}`;
}

api.interceptors.request.use((config) => {
  const token = getToken();
  if (token && !isAuthEndpoint(config.url)) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const original = error.config as InternalAxiosRequestConfig & { _retry?: boolean };

    const shouldRefresh =
      error.response?.status === 401 &&
      original &&
      !original._retry &&
      !isAuthEndpoint(original.url);

    if (shouldRefresh) {
      original._retry = true;
      try {
        const token = await refreshAccessToken();
        original.headers.Authorization = `Bearer ${token}`;
        return api(original);
      } catch {
        redirectToLogin();
      }
    }

    return Promise.reject(normalizeApiError(error));
  },
);
