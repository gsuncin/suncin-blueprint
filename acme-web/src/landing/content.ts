/** Every word on the landing page, in one file.
 *
 * Copy changes far more often than layout, and by far more people. Keeping it
 * here means a wording change is a one-line diff nobody has to review for
 * rendering regressions.
 */

export const HERO = {
  headline: "Ship the boring parts once",
  subhead:
    "A monorepo template with a gateway, a BFF, a stateless service, and the deployment that carries them.",
  primaryCta: { label: "Get started", href: "/login" },
  secondaryCta: { label: "Read the constitution", href: "#principles" },
};

export const PRINCIPLES = [
  {
    title: "One way in",
    body: "The gateway is the only container with a published port. Everything else is reachable by name on an internal network, and a script asserts it in CI.",
  },
  {
    title: "Integrations never block the domain",
    body: "A provider being down produces a failure-marked row, not an exception. The work still gets recorded.",
  },
  {
    title: "Two gates, never collapsed",
    body: "What the plan includes and what the role allows are separate questions with separate answers, so a limit can say which one it is.",
  },
  {
    title: "A green suite is the exit gate",
    body: "Tests come first and the whole suite runs before anything is called done. A red suite is information; a fudged green one is a lie.",
  },
];

export const FAQ = [
  {
    question: "Why a gateway when there is one back-end?",
    answer:
      "So there can be a second one later. The verifier holds only a public key, so onboarding another service means trusting a URL rather than sharing a secret.",
  },
  {
    question: "Why is the microservice stateless?",
    answer:
      "One party owns the data. The service can be redeployed, scaled or destroyed without a migration, and a leaked credential at rest is not possible where nothing is stored.",
  },
  {
    question: "Does this run on one box?",
    answer:
      "Yes, and that is the design point. Terraform provisions a single Ubuntu VPS with Docker Compose, a data volume, backups and a firewall.",
  },
];

export const FOOTER_NOTE = "A boilerplate. Replace this copy with your own.";
