# Architecture

## Resource hierarchy this repository builds

```mermaid
flowchart TB
  org[Organization<br/>org policies, audit sink, data access logs]
  org --> iac[prefix-pr-iac-core<br/>state buckets, CMEK, WIF, automation SAs]
  org --> bill[prefix-pr-billing<br/>billing export bucket]
  org --> log[prefix-pr-logging<br/>org-audit and org-network log buckets, access logs]
  org --> infra[Infrastructure]
  org --> wl[Workloads]
  infra --> net[Network]
  net --> hub[prefix-pr-net-core<br/>hub project]
  net --> pspoke[prefix-prod-net-spoke<br/>prod Shared VPC host]
  net --> nspoke[prefix-non-prod-net-spoke<br/>non-prod Shared VPC host]
  infra --> iprod[Prod]
  infra --> inp[Non-Prod]
  wl --> bu[Business Unit N]
  bu --> bprod[Prod<br/>workload projects]
  bu --> bnp[Non-Prod<br/>workload projects]
```

Core projects sit directly under the organization on purpose: they must survive any folder reorganization and must not inherit folder-level policy exceptions.

## Who can run Terraform

```mermaid
sequenceDiagram
  participant Run as Plan or apply run
  participant GH as GitHub OIDC
  participant WIF as Workload identity pool (iac-core)
  participant SA as dev-terraform-execute
  Run->>GH: request token (sub = repo, any ref)
  GH->>WIF: token
  WIF->>SA: allowed by attribute.repository
  Note over SA: the apply workflow also waits for the production environment
```

- `dev-terraform-execute` in the iac-core project runs Terraform for this repository, `gcp-infrastructure-lz` and every workload project. `sa-billing-reader` and `sa-logging-reader` cannot run Terraform.
- Any ref of a bound repository can impersonate that account, so a pull-request plan uses an account that can write. Plans still run with `-lock=false`.
- The apply workflow runs only from `main`, after a human approves the `production` environment.
- The provider rejects tokens from any other GitHub owner. It accepts the pipeline repositories, every repository named in a `4-workload-projects` YAML file, and `additional_repositories` (the `cicd-runners` repository). `cicd-runners` may mint a token and does not get `dev-terraform-execute`.

## State

| Bucket | Holds | Written by |
|---|---|---|
| `<prefix>-pr-tfstate-bootstrap` | state of this repository, prefix `bootstrap/<stage>` | `dev-terraform-execute` |
| `<prefix>-pr-tfstate-lz` | state of `gcp-infrastructure-lz` | `dev-terraform-execute` |
| `<project-id>-tfstate` | state of one workload repository, encrypted with that project's key | `dev-terraform-execute` |

Buckets are versioned, CMEK-encrypted (state buckets in `iac-core`), uniform-access, public access prevented and access-logged. `dev-terraform-execute` has `objectAdmin` on each of them.

## Cross-repository contract

`gcp-infrastructure-lz` reads output `projects` from state prefix `bootstrap/3-workload-projects` (directory `4-workload-projects`) and attaches those projects to the Shared VPC hosts. It does not create the hub or the host projects. Those ids are fixed in `gcp-terraform-module/modules/naming` and the projects are created by `2-network-projects` under `infrastructure/network`. `1-org.folder_ids` and `2-network-projects.projects` stay stable outputs. Changing any of those names, or a network project id, is a breaking change and needs a coordinated PR in the landing-zone repository. The cicd state prefix stays `bootstrap/2-cicd-identity`.
