import { CircularProgress, Box } from "@mui/material";
import { lazy, Suspense } from "react";
import { BrowserRouter, Route, Routes } from "react-router-dom";

import AppLayout from "@/components/AppLayout";
import PrivateRoute from "@/components/PrivateRoute";
import RequireRole from "@/components/RequireRole";

// Lazy per route. MUI plus the table stack is a large first paint, and the
// login page — the only one an anonymous visitor sees — should not carry the
// dashboard's weight.
const LoginPage = lazy(() => import("@/pages/Login"));
const DashboardPage = lazy(() => import("@/pages/Dashboard"));
const RecordsPage = lazy(() => import("@/pages/Records"));
const UsersSettingsPage = lazy(() => import("@/pages/Settings/Users"));

function RouteFallback() {
  return (
    <Box sx={{ display: "grid", placeItems: "center", minHeight: "50vh" }}>
      <CircularProgress aria-label="Loading" />
    </Box>
  );
}

export default function AppRoutes() {
  return (
    <BrowserRouter>
      <Suspense fallback={<RouteFallback />}>
        <Routes>
          <Route path="/login" element={<LoginPage />} />

          {/* Gate one: authenticated. */}
          <Route element={<PrivateRoute />}>
            <Route element={<AppLayout />}>
              <Route index element={<DashboardPage />} />
              <Route path="records" element={<RecordsPage />} />

              {/* Gate two: role. The plan gate is applied inside the page,
                  because an unentitled user should see the feature and be told
                  their plan does not include it — not be redirected away. */}
              <Route element={<RequireRole resource="users" capability="manage" />}>
                <Route path="settings/users" element={<UsersSettingsPage />} />
              </Route>
            </Route>
          </Route>
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
