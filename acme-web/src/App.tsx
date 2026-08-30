import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import { QueryClientProvider } from "@tanstack/react-query";

import { AuthProvider } from "@/context/AuthProvider";
import AppRoutes from "@/routes/routes";
import { queryClient } from "@/services/queryClient";
import { theme } from "@/theme";

export default function App() {
  return (
    <ThemeProvider theme={theme} defaultMode="system">
      <CssBaseline />
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <AppRoutes />
        </AuthProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
}
