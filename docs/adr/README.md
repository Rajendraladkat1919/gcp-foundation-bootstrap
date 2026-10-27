# Architecture decision records

| ADR | Decision |
|---|---|
| [0001](0001-staged-layout-and-state.md) | Four stages, one state each |
| [0002](0002-oidc-plan-and-apply-identities.md) | OIDC only. Separate plan and apply identities are superseded by 0006 |
| [0003](0003-modules-from-internal-repo-by-tag.md) | Modules come from `gcp-terraform-module`, pinned by tag |
| [0004](0004-apply-after-merge-with-approval.md) | Apply on merge, behind an environment approval |
| [0005](0005-network-host-projects-in-bootstrap.md) | Hub and Shared VPC host projects are created under the Network folder |
| [0006](0006-one-terraform-service-account.md) | One service account, `dev-terraform-execute`, runs all Terraform |

Add a new file with the next number for every decision that is expensive to reverse. Do not edit an accepted ADR, supersede it.
