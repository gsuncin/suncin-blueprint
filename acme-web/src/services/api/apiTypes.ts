export interface ResponsePaginated<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export interface ApiError {
  isApiError: true;
  message: string;
  status?: number;
  code?: string;
  data?: unknown;
}

/** Dig a human-readable message out of a DRF error body.
 *
 * DRF puts the message in a different place depending on what rejected the
 * request: `detail` for a permission class, a field name for a serializer,
 * `non_field_errors` for a validator. Handling only one of them means the user
 * sees "Request failed with status code 400" for the other two.
 */
function firstMessage(payload: unknown): string | undefined {
  if (typeof payload === "string") return payload;
  if (Array.isArray(payload)) {
    for (const item of payload) {
      const found = firstMessage(item);
      if (found) return found;
    }
    return undefined;
  }
  if (payload && typeof payload === "object") {
    const body = payload as Record<string, unknown>;
    for (const key of ["detail", "error", "message", "non_field_errors"]) {
      const found = firstMessage(body[key]);
      if (found) return found;
    }
    for (const [field, value] of Object.entries(body)) {
      const found = firstMessage(value);
      if (found) return `${field}: ${found}`;
    }
  }
  return undefined;
}

export function normalizeApiError(error: unknown): ApiError {
  const candidate = error as {
    response?: { status?: number; data?: unknown };
    message?: string;
  };
  const data = candidate?.response?.data;

  return {
    isApiError: true,
    status: candidate?.response?.status,
    // The BFF sends a distinct code for a plan denial so the UI can offer an
    // upgrade instead of saying "forbidden" (C-2).
    code:
      data && typeof data === "object" && "code" in data
        ? String((data as { code: unknown }).code)
        : undefined,
    message: firstMessage(data) ?? candidate?.message ?? "Something went wrong.",
    data,
  };
}
