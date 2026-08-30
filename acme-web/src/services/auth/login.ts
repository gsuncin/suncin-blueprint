import { api } from "@/services/api/api";

export interface LoginPayload {
  email: string;
  password: string;
}

/** The refresh token is NOT in this response — it arrives as an HttpOnly
 * cookie the browser stores and JavaScript never sees. */
export async function doLogin(payload: LoginPayload): Promise<string> {
  const response = await api.post<{ access: string }>("/auth/token/", payload);
  return response.data.access;
}

export async function doLogout(): Promise<void> {
  await api.post("/auth/token/logout/", {});
}
