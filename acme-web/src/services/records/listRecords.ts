import { api } from "@/services/api/api";
import type { ResponsePaginated } from "@/services/api/apiTypes";
import type { ExampleRecord } from "@/types/record";

export interface ListRecordsParams {
  page?: number;
  status?: string;
}

export async function listRecords(
  params: ListRecordsParams = {},
): Promise<ResponsePaginated<ExampleRecord>> {
  const search = new URLSearchParams();
  if (params.page) search.set("page", String(params.page));
  if (params.status) search.set("status", params.status);

  const response = await api.get<ResponsePaginated<ExampleRecord>>(
    `/example/records/?${search.toString()}`,
  );
  return response.data;
}
