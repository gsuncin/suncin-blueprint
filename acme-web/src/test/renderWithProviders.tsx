import { ThemeProvider } from "@mui/material/styles";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderOptions } from "@testing-library/react";
import type { ReactElement, ReactNode } from "react";
import { MemoryRouter } from "react-router-dom";

import { AuthContext, type AuthState } from "@/context/authState";
import { theme } from "@/theme";
import type { User } from "@/types/user";

interface Options extends Omit<RenderOptions, "wrapper"> {
  route?: string;
  /** Pass a user to render as signed in. Omit for an anonymous render. */
  user?: User | null;
  isAuthLoading?: boolean;
}

/**
 * Render a component with every provider the app gives it.
 *
 * Auth is supplied through the real AuthContext rather than by mocking the
 * useAuth module. Mocking the hook would keep passing if the provider stopped
 * supplying a field the component reads — the test would be asserting against
 * its own fixture rather than against the wiring.
 *
 * A fresh QueryClient per test: sharing one lets a cached result from an
 * earlier test satisfy a later query, so the later test passes without its own
 * mock ever being called. Retries are off so an error-path assertion does not
 * wait out the retry schedule.
 */
export function renderWithProviders(
  ui: ReactElement,
  { route = "/", user = null, isAuthLoading = false, ...options }: Options = {},
) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });

  const auth: AuthState = {
    user,
    token: user ? "test-access-token" : "",
    isAuthLoading,
    signIn: async () => {},
    signOut: () => {},
  };

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <ThemeProvider theme={theme}>
        <QueryClientProvider client={queryClient}>
          <AuthContext.Provider value={auth}>
            <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>
          </AuthContext.Provider>
        </QueryClientProvider>
      </ThemeProvider>
    );
  }

  return { queryClient, ...render(ui, { wrapper: Wrapper, ...options }) };
}
