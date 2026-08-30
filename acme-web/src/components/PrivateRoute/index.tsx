import { Navigate, Outlet, useLocation } from "react-router-dom";

import { useAuth } from "@/hooks/useAuth";

/** Gate one: is anyone signed in? */
export default function PrivateRoute() {
  const { isAuthLoading, token } = useAuth();
  const location = useLocation();

  // Render nothing rather than redirecting. On a hard refresh the token has
  // not been fetched yet, and redirecting here logs out every user who
  // reloads the page.
  if (isAuthLoading) return null;

  if (!token) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  return <Outlet />;
}
