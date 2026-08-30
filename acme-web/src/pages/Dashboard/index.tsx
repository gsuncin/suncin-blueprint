import { Card, CardContent, Grid, Typography } from "@mui/material";
import { useQuery } from "@tanstack/react-query";

import PageContainer from "@/components/PageContainer";
import { listRecords } from "@/services/records/listRecords";
import type { JobStatus } from "@/types/record";

const TILES: { status: JobStatus; label: string }[] = [
  { status: "PENDING", label: "Awaiting a verdict" },
  { status: "DELIVERED", label: "Delivered" },
  { status: "REJECTED", label: "Rejected by the provider" },
  { status: "ERROR", label: "Could not be attempted" },
];

export default function DashboardPage() {
  const queries = TILES.map((tile) => tile.status);

  const { data, isLoading } = useQuery({
    queryKey: ["records", "counts"],
    queryFn: async () => {
      const results = await Promise.all(
        queries.map((status) => listRecords({ status })),
      );
      return Object.fromEntries(
        queries.map((status, index) => [status, results[index].count]),
      ) as Record<JobStatus, number>;
    },
  });

  return (
    <PageContainer title="Dashboard" description="Where the work stands right now.">
      <Grid container spacing={2}>
        {TILES.map((tile) => (
          <Grid key={tile.status} size={{ xs: 12, sm: 6, md: 3 }}>
            <Card variant="outlined">
              <CardContent>
                <Typography variant="h2">
                  {isLoading ? "—" : (data?.[tile.status] ?? 0)}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {tile.label}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>
    </PageContainer>
  );
}
