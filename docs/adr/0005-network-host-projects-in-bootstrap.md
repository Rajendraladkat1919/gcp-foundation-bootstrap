# 0005: Network host projects are created under the Network folder

Status: accepted

Supersedes the placement described in the architecture diagram at the time of ADR 0001, where the landing-zone repository created the hub under Network and the Shared VPC hosts under Infrastructure / Prod and Infrastructure / Non-Prod.

## Context

The Network folder already exists. The hub and both Shared VPC hosts are one set of projects: they change rarely, they must exist before any VPC is built, and they all belong under Network rather than under the environment folders.

## Decision

Stage `2-network-projects` creates the shell only: `<prefix>-pr-net-core`, `<prefix>-prod-net-spoke` and `<prefix>-non-prod-net-spoke` in `infrastructure/network`. With prefix `demo` those are the diagram ids `demo-pr-net-core`, `demo-prod-net-spoke` and `demo-non-prod-net-spoke`. Prod and non-prod are Shared VPC hosts. `gcp-infrastructure-lz` builds the VPCs, firewall, NAT and service-project attachments in those projects and does not create the projects. The three core projects stay at the organization root.

## Consequences

- Apply this stage immediately after `1-org`, before identity, workload projects and the landing zone.
- Project ids are fixed in `gcp-terraform-module/modules/naming`. Renaming one is a breaking change for `gcp-infrastructure-lz`.
- `sa-tf-infra-prod` and `sa-tf-infra-nonprod` hold the network roles on hub and their respective spoke projects. `sa-tf-bootstrap` holds `roles/compute.xpnAdmin` on the Infrastructure and Workloads folders. See [ADR 0007](0007-five-scoped-service-accounts.md).
