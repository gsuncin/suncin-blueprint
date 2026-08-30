import { api } from "@/services/api/api";
import type { User } from "@/types/user";

/** Identity plus both gate maps, in one call.
 *
 * Fetched together on purpose: retrieved separately they can drift out of step
 * and the UI offers an action the backend then refuses.
 */
export async function getLoggedUser(): Promise<User> {
  const response = await api.get<User>("/auth/logged/");
  return response.data;
}
