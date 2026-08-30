import {
  Alert,
  Button,
  Paper,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from "@mui/material";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import EntitlementGate from "@/components/EntitlementGate";
import PageContainer from "@/components/PageContainer";
import StatusChip from "@/components/StatusChip";
import { useAuth } from "@/hooks/useAuth";
import type { ApiError } from "@/services/api/apiTypes";
import { createRecord } from "@/services/records/createRecord";
import { deliverRecord } from "@/services/records/deliverRecord";
import { listRecords } from "@/services/records/listRecords";

export default function RecordsPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [recipient, setRecipient] = useState("");
  const [error, setError] = useState<string | null>(null);

  const canManage = Boolean(user?.permissions?.example?.manage);

  const { data, isLoading } = useQuery({
    queryKey: ["records", "list"],
    queryFn: () => listRecords(),
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ["records"] });

  const create = useMutation({
    mutationFn: createRecord,
    onSuccess: () => {
      setRecipient("");
      setError(null);
      invalidate();
    },
    onError: (caught: ApiError) => setError(caught.message),
  });

  // The verdict is on the returned row, not in the HTTP status: a provider
  // failure resolves successfully with status=ERROR. See CONSTITUTION C-1.
  const deliver = useMutation({ mutationFn: deliverRecord, onSuccess: invalidate });

  const handleCreate = (event: FormEvent) => {
    event.preventDefault();
    create.mutate({ recipient });
  };

  return (
    <PageContainer title="Records" description="Each row owns one outbound job.">
      <Stack spacing={3}>
        <EntitlementGate entitlement="example_jobs" featureName="Outbound jobs">
          <Paper variant="outlined" sx={{ p: 2 }}>
            <form onSubmit={handleCreate}>
              <Stack direction={{ xs: "column", sm: "row" }} spacing={2} sx={{ alignItems: "flex-start" }}>
                <TextField label="Recipient" value={recipient} required sx={{ flexGrow: 1 }}
                  onChange={(event) => setRecipient(event.target.value)} />
                <Button type="submit" variant="contained"
                  disabled={!canManage || create.isPending}>
                  Add record
                </Button>
              </Stack>
            </form>
            {error && <Alert severity="error" sx={{ mt: 2 }}>{error}</Alert>}
          </Paper>
        </EntitlementGate>

        <TableContainer component={Paper} variant="outlined">
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>Recipient</TableCell>
                <TableCell>Status</TableCell>
                <TableCell>Detail</TableCell>
                <TableCell align="right">Actions</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {isLoading && (
                <TableRow>
                  <TableCell colSpan={4}>Loading…</TableCell>
                </TableRow>
              )}

              {!isLoading && data?.results.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4}>
                    <Typography variant="body2" color="text.secondary">
                      No records yet.
                    </Typography>
                  </TableCell>
                </TableRow>
              )}

              {data?.results.map((record) => (
                <TableRow key={record.id}>
                  <TableCell>{record.recipient}</TableCell>
                  <TableCell><StatusChip status={record.status} /></TableCell>
                  <TableCell>
                    <Typography variant="body2" color="text.secondary">
                      {record.error_code || record.message || "—"}
                    </Typography>
                  </TableCell>
                  <TableCell align="right">
                    <Button size="small" disabled={!canManage || deliver.isPending}
                      onClick={() => deliver.mutate(record.id)}>
                      Deliver
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Stack>
    </PageContainer>
  );
}
