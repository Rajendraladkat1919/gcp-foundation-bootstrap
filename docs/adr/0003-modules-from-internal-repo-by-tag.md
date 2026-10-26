# 0003: Modules come from `gcp-terraform-module`, pinned by tag

Status: accepted

## Context

The landing zone is built on Cloud Foundation Fabric. Consuming upstream directly means upgrades land unreviewed. Copying modules into each repository means drift.

## Decision

Fabric **v59.1.0** is vendored once into `gcp-terraform-module` (provenance and hashes in its `modules/PROVENANCE.md`). Stages reference `git::https://github.com/ORG/gcp-terraform-module.git//modules/<name>?ref=v59.1.0`. Upgrading means re-vendoring, tagging, and a PR here that moves the tag, with a plan that shows the effect.

## Consequences

- CI needs read access to the modules repository (`MODULES_READ_TOKEN`).
- `scripts/validate-local.sh` validates against a sibling checkout without any network access to it.
- The `ORG` placeholder is replaced once with `make set-org`.
