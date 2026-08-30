import { Alert, Box, Button, Card, Stack, TextField, Typography } from "@mui/material";
import { useState, type FormEvent } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";

import { useAuth } from "@/hooks/useAuth";
import type { ApiError } from "@/services/api/apiTypes";
import { doLogin } from "@/services/auth/login";

export default function LoginPage() {
  const { signIn } = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      await signIn(await doLogin({ email, password }));
      // Only ever a same-site path: `redirect` comes from the query string,
      // and honouring an absolute URL would make this an open redirect.
      const redirect = params.get("redirect");
      navigate(redirect?.startsWith("/") ? redirect : "/", { replace: true });
    } catch (caught) {
      setError((caught as ApiError).message ?? "Could not sign in.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Box sx={{ display: "grid", placeItems: "center", minHeight: "100vh", p: 2 }}>
      <Card sx={{ p: 4, width: "100%", maxWidth: 400 }} variant="outlined">
        <Typography variant="h1" sx={{ fontSize: "1.5rem", mb: 3 }}>
          Sign in
        </Typography>

        <form onSubmit={handleSubmit}>
          <Stack spacing={2}>
            {error && <Alert severity="error">{error}</Alert>}
            <TextField label="Email" type="email" value={email} required autoComplete="email"
              onChange={(event) => setEmail(event.target.value)} />
            <TextField label="Password" type="password" value={password} required
              autoComplete="current-password"
              onChange={(event) => setPassword(event.target.value)} />
            <Button type="submit" variant="contained" disabled={isSubmitting}>
              {isSubmitting ? "Signing in…" : "Sign in"}
            </Button>
          </Stack>
        </form>
      </Card>
    </Box>
  );
}
