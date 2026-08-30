# Backlog

Pending work that does not yet belong to a workstream. Grouped by area.
Severity is about consequence, not effort.

| ID | Item | Severity | Notes |
|---|---|---|---|
| INFRA-1 | Terraform remote state is configured but the bucket is created by hand | Medium | `envs/oci/backend.tf.example` documents it; bootstrapping a bucket with Terraform that stores state in it is a chicken-and-egg |
| WEB-1 | No visual regression testing | Low | Playwright screenshots would catch layout breaks Lighthouse does not |
| BFF-1 | No OpenAPI schema published | Medium | `drf-spectacular` would give the gateway and third parties a contract to generate from |
