import { Alert, AlertTitle, Button } from "@mui/material";
import type { ReactNode } from "react";

import { useEntitlement } from "@/hooks/useEntitlement";
import type { Entitlement } from "@/types/user";

interface Props {
  entitlement: Entitlement;
  featureName: string;
  children: ReactNode;
}

/**
 * Renders children when the plan includes the feature, and an upgrade prompt
 * when it does not.
 *
 * Deliberately NOT `return null`. A feature the user cannot see is a feature
 * they cannot buy, and "you have no permission" is the wrong message for a
 * plan limit — it sends them to their admin instead of to the pricing page.
 */
export default function EntitlementGate({ entitlement, featureName, children }: Props) {
  const entitled = useEntitlement(entitlement);
  if (entitled) return <>{children}</>;

  return (
    <Alert
      severity="info"
      action={
        <Button color="inherit" size="small" href="/settings/plan">
          See plans
        </Button>
      }
    >
      <AlertTitle>{featureName} is not in your plan</AlertTitle>
      Upgrade to enable it for everyone in your account.
    </Alert>
  );
}
