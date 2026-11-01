# 0003: Modules sourced directly from Cloud Foundation Fabric, pinned by SHA

Status: accepted (supersedes the tag-pinned internal mirror approach)

## Context

The landing zone is built on Cloud Foundation Fabric (CFF). The original approach vendored CFF into a private `gcp-terraform-module` mirror and pinned by release tag. This introduced operational overhead (mirror sync, `MODULES_READ_TOKEN`, `make set-org` placeholder replacement) and triggered `CKV_TF_1` (checkov requires SHA pinning, not tag pinning).

## Decision

All modules are sourced directly from the official CFF GitHub repository, pinned to a specific commit SHA:

```
source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/<name>?ref=<SHA>"
```

**Current SHA:** `5b9de0cf7bb5163ef8d0fa4973f31dd36b6de528` (CFF **v59.2.0**)

SHA pinning (not tag pinning) is used because:
- Tags are mutable — a force-push can change what a tag points to
- SHAs are immutable — the exact commit is guaranteed forever
- SHA pinning satisfies `CKV_TF_1` so the checkov skip is removed

Upgrading means updating the `?ref=SHA` in all module `source` lines to the new version's commit SHA. A single `sed` or `perl` command updates all files in one pass.

## Consequences

- `MODULES_READ_TOKEN` GitHub secret is no longer needed — CFF is public.
- `scripts/ci-modules.sh` (previously downloaded the mirror) is removed.
- `scripts/validate-local.sh` (previously validated against a sibling checkout) is removed.
- `make set-org` placeholder replacement is no longer needed.
- `CKV_TF_1` skip is removed from `.checkov.yaml` — SHA pinning satisfies the control.
- `terraform init` fetches modules from GitHub. The first `init` requires internet access.
- Lock files (`.terraform.lock.hcl`) must be regenerated after a SHA upgrade with `terraform init -upgrade`.
