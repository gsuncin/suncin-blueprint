import { Paper, Table, TableBody, TableCell, TableHead, TableRow } from "@mui/material";

import PageContainer from "@/components/PageContainer";
import { useAuth } from "@/hooks/useAuth";
import { USER_ROLE_LABELS } from "@/types/user";

/** Reached only through RequireRole resource="users" capability="manage". */
export default function UsersSettingsPage() {
  const { user } = useAuth();

  return (
    <PageContainer title="Users" description="Who can do what inside this account.">
      <Paper variant="outlined">
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>Email</TableCell>
              <TableCell>Role</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {user && (
              <TableRow>
                <TableCell>{user.email}</TableCell>
                <TableCell>{USER_ROLE_LABELS[user.role]}</TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </Paper>
    </PageContainer>
  );
}
