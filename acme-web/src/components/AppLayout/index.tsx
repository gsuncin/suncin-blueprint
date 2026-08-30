import { Box, Button, Container, Stack, Toolbar, Typography } from "@mui/material";
import AppBar from "@mui/material/AppBar";
import { Link as RouterLink, NavLink, Outlet } from "react-router-dom";

import { useAuth } from "@/hooks/useAuth";
import { doLogout } from "@/services/auth/login";
import { queryClient } from "@/services/queryClient";
import type { ResourceArea } from "@/types/user";

interface NavItem {
  to: string;
  label: string;
  resource: ResourceArea;
}

const NAV: NavItem[] = [
  { to: "/", label: "Dashboard", resource: "example" },
  { to: "/records", label: "Records", resource: "example" },
  { to: "/settings/users", label: "Users", resource: "users" },
];

export default function AppLayout() {
  const { user, signOut } = useAuth();

  const handleSignOut = async () => {
    try {
      await doLogout();
    } finally {
      // Clear locally whatever the server said. A failed logout call must not
      // leave the user looking signed in, and the cached data belongs to a
      // session that is over.
      queryClient.clear();
      signOut();
    }
  };

  // The same matrix that guards the routes also builds the nav, so a link can
  // never point at a page the user will be bounced out of.
  const visible = NAV.filter((item) => user?.permissions?.[item.resource]?.view);

  return (
    <Box sx={{ minHeight: "100vh", bgcolor: "background.default" }}>
      <AppBar position="static" color="default" elevation={0}>
        <Toolbar>
          <Typography variant="h3" component={RouterLink} to="/"
            sx={{ mr: 4, textDecoration: "none", color: "inherit" }}>
            Acme
          </Typography>

          <Stack direction="row" spacing={1} sx={{ flexGrow: 1 }} component="nav">
            {visible.map((item) => (
              <Button key={item.to} component={NavLink} to={item.to} end={item.to === "/"}
                sx={{ "&.active": { fontWeight: 700, textDecoration: "underline" } }}>
                {item.label}
              </Button>
            ))}
          </Stack>

          <Typography variant="body2" color="text.secondary" sx={{ mr: 2 }}>
            {user?.email}
          </Typography>
          <Button onClick={handleSignOut}>Sign out</Button>
        </Toolbar>
      </AppBar>

      <Container maxWidth="lg">
        <Outlet />
      </Container>
    </Box>
  );
}
