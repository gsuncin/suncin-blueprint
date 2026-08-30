import { api } from "@/services/api/api";
import type { ExampleRecord } from "@/types/record";

/** Always resolves for a reachable BFF, even when the provider failed.
 *
 * The verdict is in `status` and `error_code` on the returned row, not in the
 * HTTP status — that is the client-side half of C-1. Treating a delivery
 * failure as a rejected promise would put provider trouble in the same bucket
 * as a network error, and they need different messages.
 */
export async function deliverRecord(id: string): Promise<ExampleRecord> {
  const response = await api.post<ExampleRecord>(`/example/records/${id}/deliver/`);
  return response.data;
}
