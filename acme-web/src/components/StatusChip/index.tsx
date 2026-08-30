import { Chip } from "@mui/material";

import type { JobStatus } from "@/types/record";

const APPEARANCE: Record<JobStatus, { label: string; color: "default" | "success" | "warning" | "error" }> = {
  PENDING: { label: "Pending", color: "default" },
  DELIVERED: { label: "Delivered", color: "success" },
  // Their "no" and our "could not ask" look the same to a user unless the UI
  // distinguishes them, and only one of the two is worth retrying.
  REJECTED: { label: "Rejected", color: "warning" },
  ERROR: { label: "Failed", color: "error" },
};

export default function StatusChip({ status }: { status: JobStatus }) {
  const { label, color } = APPEARANCE[status] ?? APPEARANCE.PENDING;
  return <Chip size="small" label={label} color={color} variant="outlined" />;
}
