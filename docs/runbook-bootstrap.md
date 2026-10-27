# Runbook: first apply

This is the only time a human applies Terraform in this repository. It is a one-off and needs elevated access, so do it with a second person watching, and write down the time and who did it.

## 0. Prerequisites

- A Google Cloud organization, a billing account, and Cloud Identity groups for platform engineers and each business unit
- The person applying has, **temporarily**: `roles/resourcemanager.organizationAdmin`, `roles/resourcemanager.projectCreator`, `roles/resourcemanager.folderAdmin`, `roles/orgpolicy.policyAdmin`, `roles/logging.configWriter` on the organization, and `roles/billing.user` on the billing account
- `gcloud auth application-default login` done as that person
- The GitHub organization exists, with these repositories: `gcp-terraform-module`, `gcp-foundation-bootstrap`, `gcp-infrastructure-lz`
- `gcp-terraform-module` has the tag `v59.1.0` pushed (the tag every `source = ...?ref=v59.1.0` points at)
- Tools from the README are installed, and `make hooks` has been run

## 1. Fill in configuration

```bash
make set-org ORG=<github-org>
$EDITOR 0-core-projects/terraform.tfvars 1-org/terraform.tfvars 2-network-projects/terraform.tfvars 3-cicd-identity/terraform.tfvars 4-workload-projects/terraform.tfvars
# Only if gcp-terraform-module is private. Remove it again afterwards.
git config --global url."https://x-access-token:<token>@github.com/".insteadOf "https://github.com/"
make validate MODULES=../gcp-terraform-module
```

## 2. Stage 0: core projects (local state first)

The state bucket does not exist yet, so the first apply uses local state and then moves it.

```bash
cd 0-core-projects
mv backend.tf /tmp/backend.tf.bak          # run on local state
terraform init
terraform plan -out=tfplan
terraform apply tfplan

mv /tmp/backend.tf.bak backend.tf          # move state into the new bucket
BUCKET=$(terraform output -json state_buckets | jq -r .bootstrap)
terraform init -migrate-state -backend-config="bucket=${BUCKET}"
rm -f terraform.tfstate terraform.tfstate.backup tfplan
```

The person who ran this is now Owner of `iac-core` (the creator of a project is made Owner). That is needed for the next two stages and is removed in step 6.

## 3. Stages 1, 2 and 3

```bash
for stage in 1-org 2-network-projects 3-cicd-identity; do
  (cd "$stage" && terraform init -backend-config="bucket=${BUCKET}" && terraform plan -out=tfplan && terraform apply tfplan && rm -f tfplan)
done
```

## 4. Configure GitHub

Set the variables and secret listed in the README for this repository and for `gcp-infrastructure-lz`, then:

```bash
make protect REPO=<github-org>/gcp-foundation-bootstrap TEAM=<reviewer-team-slug>
```

That creates the branch ruleset (two approvals, code owners, signed commits, linear history, required checks `plan-gate`, `pre-commit`, `pr-title`, `dependency-review`) and the `production` environment with required reviewers and `main`-only deployment. Turn on in the repository settings: secret scanning, push protection, Dependabot alerts, and require 2FA for the organization.

## 5. Prove the pipeline

1. Open a PR with a trivial change (a label in `0-core-projects/main.tf`). Expect a plan comment per touched stage and green checks.
2. Merge it. Approve the `production` run. Expect `apply` to finish with no changes besides the label.
3. Open a pull request from a feature branch. Expect fmt, tflint, validate, checkov, drift, then a plan comment. A nightly run opens an issue when `main` does not match Google Cloud. Apply from the Actions tab on `main` with action `apply`, after that plan looks right. Do not add destroy to the workflow.
4. A pull request of this repository can impersonate `dev-terraform-execute`. That is expected. The apply workflow still waits for the `production` environment.

## 6. Remove the break-glass access

```bash
# Replace with the email of the person who ran the first apply.
for p in iac-core billing logging; do
  gcloud projects remove-iam-policy-binding "<prefix>-pr-${p}" --member="user:<email>" --role="roles/owner"
done
```

Then remove the temporary organization roles from step 0. After this, nobody holds standing write access to the foundation. Record the date in the change ticket.

## 7. Stages 3 and 4

Workload projects from here are a pull request: add `4-workload-projects/data/projects/<name>.yaml`, review the plan, merge, approve.

`2-network-projects` creates the hub and the two Shared VPC hosts under the Network folder. Apply it after `1-org` and before `gcp-infrastructure-lz`. On an organization that already has the core, org, identity and workload stages, open a pull request that adds `2-network-projects` and apply that stage only.

## Recovery

| Situation | Action |
|---|---|
| CI cannot authenticate | Check `WIF_PROVIDER`, the repository name in stage 3 `pipelines`, and that an apply run is on `main` with the `production` environment approved |
| State bucket unreachable | Do not recreate it. The bucket is versioned: restore the previous generation of the state object. |
| Locked state | `terraform force-unlock <id>` only after confirming no run is active |
| Somebody changed a resource by hand | The drift issue shows the diff. Revert by hand or let the next apply do it, never both |
