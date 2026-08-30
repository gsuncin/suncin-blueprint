import { api } from "@/services/api/api";
import type { ExampleRecord } from "@/types/record";

export interface CreateRecordPayload {
  recipient: string;
  locale?: string;
}

export async function createRecord(payload: CreateRecordPayload): Promise<ExampleRecord> {
  const response = await api.post<ExampleRecord>("/example/records/", payload);
  return response.data;
}
