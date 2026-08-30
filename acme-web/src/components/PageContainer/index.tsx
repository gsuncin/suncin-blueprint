import { Box, Stack, Typography } from "@mui/material";
import type { ReactNode } from "react";

interface Props {
  title: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
}

export default function PageContainer({ title, description, action, children }: Props) {
  return (
    <Box component="main" sx={{ py: 3 }}>
      <Stack
        direction={{ xs: "column", sm: "row" }}
        spacing={2}
        sx={{
          mb: 3,
          justifyContent: "space-between",
          alignItems: { xs: "flex-start", sm: "center" },
        }}
      >
        <Box>
          <Typography variant="h1" sx={{ fontSize: "1.75rem" }}>
            {title}
          </Typography>
          {description && (
            <Typography variant="body2" color="text.secondary">
              {description}
            </Typography>
          )}
        </Box>
        {action}
      </Stack>
      {children}
    </Box>
  );
}
