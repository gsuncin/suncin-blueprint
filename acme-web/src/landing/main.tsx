import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import LandingApp from "@/landing/App";

// No Sentry, no auth context, no router, no query client. This entry exists to
// stay small: everything imported here is downloaded by every anonymous
// visitor, and src/landing/pageBudget.test.ts fails the build if it grows.
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <LandingApp />
  </StrictMode>,
);
