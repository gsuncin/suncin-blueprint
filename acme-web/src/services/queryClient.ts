import { QueryClient } from "@tanstack/react-query";

import type { ApiError } from "@/services/api/apiTypes";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: (failureCount, error) => {
        // TanStack types this as Error; our interceptor rejects with an
        // ApiError, which is a structural shape rather than a subclass.
        const status = (error as unknown as ApiError)?.status;
        // Never retry what will fail identically: the answer to 401, 403 and
        // 404 does not change by asking again, and retrying a 401 races the
        // refresh interceptor that is already handling it.
        if (status && status >= 400 && status < 500) return false;
        return failureCount < 2;
      },
    },
    mutations: {
      // A mutation is a side effect. Retrying one automatically is how you get
      // two of something the user asked for once.
      retry: false,
    },
  },
});
