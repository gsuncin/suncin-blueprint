export type JobStatus = "PENDING" | "DELIVERED" | "REJECTED" | "ERROR";

export interface ExampleRecord {
  id: string;
  recipient: string;
  locale: string;
  status: JobStatus;
  message: string;
  provider_reference: string;
  /** Set when the domain could not get an answer. See CONSTITUTION C-1. */
  error_code: string;
  error_message: string;
  delivered_at: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}
