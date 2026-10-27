# Run the bootstrap from a local machine or Cloud Shell

Step-by-step apply of `gcp-foundation-bootstrap`. Stages run in order: `0-core-projects`, `1-org`, `2-network-projects`, `3-cicd-identity`, `4-workload-projects`.

What those stages create, which roles they need, and which policies they set is [bootstrap-deployment.md](bootstrap-deployment.md).

This organization has already been applied through stage 3. Use [Apply a change to an existing stage](#apply-a-change-to-an-existing-stage) for later edits. Use [First apply](#first-apply) only on an empty organization, or to understand the order that was used.

Do not run `terraform destroy`. Projects are `deletion_policy = PREVENT` and folders are `deletion_protection = true`. A destroy of stage 1 would also try to delete organization policies this stage manages.

## Values used by every command

| Name | Value |
|---|---|
| Sign-in | `operator@example.com` |
| Organization | `organizations/000000000000` |
| Billing account | `000000-000000-000000` |
| Directory customer | `C00000000` |
| Domain | `example.com` |
| Prefix | `demo` |
| Region | `us-west2` |
| GitHub organization | `<github-org>` |
| State bucket | `demo-pr-tfstate-bootstrap` |
| Landing-zone state bucket | `demo-pr-tfstate-lz` |
| Terraform | `1.16.6` |
| Providers | `hashicorp/google` and `hashicorp/google-beta` `~> 8.5` (lock file resolved `8.8.1`) |

The state bucket name is not written in `backend.tf`. Every `terraform init` passes it:

```bash
terraform init -backend-config="bucket=demo-pr-tfstate-bootstrap"
```

Prefixes inside that bucket:

| Directory | Prefix |
|---|---|
| `0-core-projects` | `bootstrap/0-core-projects` |
| `1-org` | `bootstrap/1-org` |
| `2-network-projects` | `bootstrap/2-network-projects` |
| `3-cicd-identity` | `bootstrap/2-cicd-identity` |
| `4-workload-projects` | `bootstrap/3-workload-projects` |

## 1. Checkout layout

Module sources in the stage files are `../../gcp-terraform-module/modules/...`. From a stage directory, that path is the sibling repository. Both checkouts have to sit next to each other:

```text
repos/
├── gcp-foundation-bootstrap/
│   ├── 0-core-projects/
│   ├── 1-org/
│   ├── 2-network-projects/
│   ├── 3-cicd-identity/
│   └── 4-workload-projects/
└── gcp-terraform-module/
    └── modules/
```

On the machine that applied this organization, that tree is:

```text
/Users/rajendraladkat/project-work/gcp-bkp/repos/gcp-foundation-bootstrap
/Users/rajendraladkat/project-work/gcp-bkp/repos/gcp-terraform-module
```

CI is intended to use `git::https://github.com/<github-org>/gcp-terraform-module.git//modules/...?ref=v59.1.0`. Leave the local paths in place for a local or Cloud Shell apply. Do not commit a switch back to the git source until the modules repository and tag `v59.1.0` exist and CI can read them.

Confirm the layout before init:

```bash
ls ../../gcp-terraform-module/modules/project
```

Run that from `0-core-projects`. It must print the module files, not "No such file".

## 2. Tools

### Local machine (macOS)

```bash
terraform version
```

The version line must be `Terraform v1.16.6`. Install that exact version with `tfenv` if the system Terraform is different:

```bash
brew install tfenv
tfenv install 1.16.6
tfenv use 1.16.6
```

`gcloud` must be installed and able to print a token:

```bash
gcloud version
gcloud auth login operator@example.com
gcloud config set account operator@example.com
```

Optional, used by the repository's `make` targets and not required to apply: pre-commit `>= 3.7`, tflint `>= 0.60`, terraform-docs `>= 0.24`, checkov `3.3.30`.

### Cloud Shell

Cloud Shell already has `gcloud` and is signed in as the account that opened the shell. Open the shell from the Google Cloud console while logged in as `operator@example.com`. Confirm:

```bash
gcloud auth list
gcloud config get-value account
```

The active account must be `operator@example.com`. If it is not:

```bash
gcloud config set account operator@example.com
```

Cloud Shell's preinstalled Terraform is often a different version. Install `1.16.6` into the home directory, which persists across sessions:

```bash
cd "$HOME"
curl -fsSL -o terraform.zip \
  https://releases.hashicorp.com/terraform/1.16.6/terraform_1.16.6_linux_amd64.zip
unzip -o terraform.zip
mkdir -p "$HOME/bin"
mv terraform "$HOME/bin/terraform"
chmod +x "$HOME/bin/terraform"
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"
terraform version
```

`uname -m` prints `aarch64` on an Arm Cloud Shell. Use `terraform_1.16.6_linux_arm64.zip` in that case. If that download returns 404, install the same version already used for the successful local apply (`terraform version` on that machine) rather than Cloud Shell's default Terraform.

Clone or upload both repositories into `$HOME` with the same sibling layout:

```text
$HOME/gcp-bkp/repos/gcp-foundation-bootstrap
$HOME/gcp-bkp/repos/gcp-terraform-module
```

Cloud Shell's disk is the home directory. State is in GCS, so closing the browser does not lose Terraform state. It does lose an unsaved `tfplan` file and an expired access token.

Set the quota project after stage 0 exists. Do not point quota at a project this user cannot use. `synapse-6811` returns `USER_PROJECT_DENIED` for `rala`.

```bash
gcloud config set project demo-pr-iac-core
```

## 3. Roles to grant before the first apply

Run these once, as a user who can administer the organization and the billing account. Skip a binding that is already present.

```bash
ORG=000000000000
USER=user:operator@example.com

for role in \
  roles/resourcemanager.organizationAdmin \
  roles/resourcemanager.projectCreator \
  roles/resourcemanager.folderAdmin \
  roles/orgpolicy.policyAdmin \
  roles/logging.configWriter
do
  gcloud organizations add-iam-policy-binding "$ORG" \
    --member="$USER" \
    --role="$role"
done
```

`roles/owner` does not grant `resourcemanager.folders.create`. Stage 1 fails with 403 until `roles/resourcemanager.folderAdmin` is present.

Billing, on the billing account:

```bash
gcloud billing accounts add-iam-policy-binding 000000-000000-000000 \
  --member="user:operator@example.com" \
  --role="roles/billing.admin"

gcloud billing accounts add-iam-policy-binding 000000-000000-000000 \
  --member="user:operator@example.com" \
  --role="roles/billing.user"
```

Confirm folder create is allowed:

```bash
gcloud organizations test-iam-permissions 000000000000 \
  --permissions=resourcemanager.folders.create,resourcemanager.projects.create
```

Both permissions must appear in the response.

## 4. Groups, created before stage 1

Create these in the Google Groups console for `example.com`. Terraform only grants them. It does not create them.

| Email |
|---|
| `platform-engineers@example.com` |
| `business-unit-0@example.com` |

`gcloud identity groups create` as `rala` returns Cloud Identity `403` error 2015 even with `roles/cloudidentity.groupsAdmin`. That role in the GCP IAM page titled "Group Admin" under hub and spoke is Network Connectivity, not Cloud Identity. The Cloud Identity role that can create groups from the API is `roles/cloudidentity.groupsAdmin`, and the directory still requires a Workspace Groups Admin or Super Admin. The console groups are the path that worked.

Stage 1 returns HTTP 400 "Group does not exist" if an address in `1-org/terraform.tfvars` differs from the group in the console.

## 5. Billing quota

A new billing account links five projects. Before stage 3, count them:

```bash
gcloud billing projects list --billing-account=000000-000000-000000
```

This account was full with:

- `example-extra-project` (display name My First Project)
- `demo-pr-iac-core`
- `demo-pr-billing`
- `demo-pr-logging`
- `demo-np-nonprod-bu-0`

`demo-pr-prod-bu-0` then failed with `Cloud billing quota exceeded`. Disable billing on the unused My First Project. Do not disable billing on any `pe-` project.

Console: Billing, account `000000-000000-000000`, Account management, menu on `example-extra-project`, Disable billing.

Or:

```bash
gcloud billing projects unlink example-extra-project
```

`hidden-cosmos-512715-j9` is in the organization and was not linked to this billing account. Leave it.

To raise the quota instead of unlinking, use [the billing quota form](https://support.google.com/code/contact/billing_quota_increase). `roles/billing.admin` can submit it.

## 6. Authenticate Terraform

`gcloud auth login` alone does not always supply the credential Terraform uses for the GCS backend. If `GOOGLE_OAUTH_ACCESS_TOKEN` is set to an old token, Terraform uses that token first and `terraform init` fails with:

```text
Error 401: Invalid Credentials, authError
```

In the same terminal, immediately before init, plan, or apply:

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
```

The token lasts about one hour. Export it again when a later command returns 401. Do not write the token into a file or into `terraform.tfvars`.

Local alternative, when you want Application Default Credentials instead of a token:

```bash
unset GOOGLE_OAUTH_ACCESS_TOKEN
gcloud auth application-default login --account=operator@example.com
```

Unset the token first. A stale token overrides ADC. Cloud Shell usually has no browser prompt for ADC. The `print-access-token` export is the path that worked there and on the local machine.

## 7. Fill terraform.tfvars

Copy `terraform.tfvars.example` to `terraform.tfvars` in each stage and fill in the real values there. Do not commit `terraform.tfvars`.

`0-core-projects/terraform.tfvars`:

```hcl
prefix             = "demo"
organization_id    = "organizations/000000000000"
billing_account_id = "000000-000000-000000"
cost_center        = "platform"
region             = "us-west2"
```

`1-org/terraform.tfvars`:

```hcl
prefix          = "demo"
organization_id = "organizations/000000000000"
domain          = "example.com"
region          = "us-west2"

groups = {
  platform_engineers = "platform-engineers@example.com"
}

business_units = {
  business-unit-0 = {
    display_name = "Business Unit 0"
    group        = "business-unit-0@example.com"
  }
}
```

`3-cicd-identity/terraform.tfvars`:

```hcl
prefix     = "demo"
github_org = "REPLACE_ME"

additional_repositories = ["cicd-runners"]

pipelines = {
  bootstrap = {
    repository = "gcp-foundation-bootstrap"
  }
  lz = {
    repository = "gcp-infrastructure-lz"
  }
}
```

`github_org` is the organization name only. A value such as `https://github.com/<github-org>` does not match GitHub's `repository_owner` claim, and the Workload Identity condition would reject every token.

`4-workload-projects/terraform.tfvars`:

```hcl
prefix             = "demo"
billing_account_id = "000000-000000-000000"
cost_center        = "platform"
region             = "us-west2"
```

Workload projects themselves are the YAML files:

- `4-workload-projects/data/projects/business-unit-0-nonprod.yaml` creates `demo-np-nonprod-bu-0` for repository `gcp-wlp-nonprod-bu-0`.
- `4-workload-projects/data/projects/business-unit-0-prod.yaml` creates `demo-pr-prod-bu-0` for repository `gcp-wlp-prod-bu-0`.

`3-cicd-identity` reads those YAML files when it builds the pool condition. Add a YAML file, apply `4-workload-projects`, then re-apply `3-cicd-identity` so the new repository is allowed to mint a token. `scripts/changed-stages.sh` encodes that order for CI. Identity state stays at `bootstrap/2-cicd-identity`. Workload state stays at `bootstrap/3-workload-projects`.

`2-network-projects/terraform.tfvars`:

```hcl
prefix             = "demo"
billing_account_id = "000000-000000-000000"
cost_center        = "platform"
```

`2-network-projects` creates three projects under Infrastructure / Network. With prefix `demo` the ids are `demo-pr-net-core`, `demo-prod-net-spoke` and `demo-non-prod-net-spoke`. This checkout uses prefix `demo`:

| Key | Project id | Shared VPC host |
|---|---|---|
| hub | `demo-pr-net-core` | no |
| prod | `demo-prod-net-spoke` | yes |
| nonprod | `demo-non-prod-net-spoke` | yes |

Apply `1-org` before `2-network-projects`. Apply `2-network-projects` before `gcp-infrastructure-lz`. On this organization the core, org, identity and workload stages are already applied, so the next bootstrap apply is `2-network-projects`.

## 8. First apply

Do this only when the state bucket does not exist yet. On this organization the bucket exists and all four stages have state in it. Skip to [Apply a change to an existing stage](#apply-a-change-to-an-existing-stage).

### Stage 0, local state, then move it

The backend block in `0-core-projects/backend.tf` points at GCS. The bucket is created by the apply, so the first apply cannot use that backend.

```bash
cd 0-core-projects
mv backend.tf /tmp/backend.tf.bak
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Read the plan before typing `yes`. It creates three projects, two state buckets, the access-log bucket, the billing-export bucket, the KMS key, and six service accounts. It must not destroy anything.

Put the backend back and migrate. Answer `yes` when Terraform asks to copy state:

```bash
mv /tmp/backend.tf.bak backend.tf
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init -migrate-state -backend-config="bucket=demo-pr-tfstate-bootstrap"
rm -f terraform.tfstate terraform.tfstate.backup tfplan
```

`terraform init -migrate-state -backend-config=...` while `backend.tf` is still commented out prints `Missing backend configuration` and leaves state on disk. The `backend "gcs"` block has to be uncommented before the migrate command.

If init stops at `Enter a value:` under `bucket`, the command was `terraform init` without `-backend-config`. Ctrl+C and rerun the init line above. Typing `demo-pr-tfstate-bootstrap` at that prompt is equivalent for that one run.

### Stage 1

```bash
cd ../1-org
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init -backend-config="bucket=demo-pr-tfstate-bootstrap"
terraform plan -out=tfplan
terraform apply tfplan
rm -f tfplan
```

Stage 1 does not read stage 0 remote state. It builds project ids from the prefix (`demo-pr-logging`, `demo-pr-iac-core`). The provider bills API calls to `demo-pr-iac-core`.

An apply is not one transaction. Resources that succeeded stay when a later resource fails. Re-run `terraform apply` after fixing the error. Do not destroy the successful folders to "start clean".

### Stage 2

```bash
cd ../3-cicd-identity
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init -backend-config="bucket=demo-pr-tfstate-bootstrap"
terraform plan -out=tfplan
terraform apply tfplan
rm -f tfplan
```

A clean first apply adds 6 resources: the pool, the provider, and four `roles/iam.workloadIdentityUser` bindings.

Record the provider name for GitHub:

```bash
terraform output workload_identity_provider_name
```

### Stage 3

Free a billing slot first ([section 5](#5-billing-quota)). Then:

```bash
cd ../4-workload-projects
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init -backend-config="bucket=demo-pr-tfstate-bootstrap"
terraform plan -out=tfplan
terraform apply tfplan
rm -f tfplan
```

The plan creates both workload projects and their keys, buckets, and identities. Approve it only when the plan says `0 to destroy`.

## 9. Apply a change to an existing stage

State is already in `demo-pr-tfstate-bootstrap`. Do not move `backend.tf` aside. Do not run `-migrate-state` again.

```bash
cd repos/gcp-foundation-bootstrap/<stage>
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init -backend-config="bucket=demo-pr-tfstate-bootstrap"
terraform plan -out=tfplan
terraform apply tfplan
rm -f tfplan
```

`<stage>` is one of `0-core-projects`, `1-org`, `2-network-projects`, `3-cicd-identity`, `4-workload-projects`. `2-network-projects` has no state yet. Init and apply it after `1-org`. A plan should add three projects and enable Shared VPC on `demo-prod-net-spoke` and `demo-non-prod-net-spoke`. Re-apply `1-org` in the same change so the Network folder grants `dev-terraform-execute` the network roles and `roles/compute.xpnAdmin`. Host enablement fails without that role.

`terraform init` with no arguments asks for the bucket. Pass `-backend-config` every time you init a fresh directory, including a new Cloud Shell clone. After a successful init, `.terraform/` remembers the bucket until the backend block changes.

A plan of `0 added, 0 changed, 0 destroyed` means the stage matches GCP. Outputs are not resources. An output-only plan still needs an apply if you want the output value stored, and that apply reports `0 changed`.

## 10. Errors hit on this organization, and the exact next command

### 401 Invalid Credentials on init

```bash
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init -backend-config="bucket=demo-pr-tfstate-bootstrap"
```

### Init says the backend configuration is missing

`backend.tf` is fully commented, or `-backend-config` was passed without a `backend "gcs"` block. Uncomment the block. Keep `bucket` out of the file. Pass it on the command line.

### KMS member is null

Already fixed in `0-core-projects/main.tf`. The Cloud Storage agent is `service-<demo-pr-iac-core project number>@gs-project-accounts.iam.gserviceaccount.com`. Do not switch it back to `google_project_service_identity.gcs.email`.

### Access logs: 412 conditionNotMet, or "do not belong to a permitted customer"

The member is `group:cloud-storage-analytics@google.com`. The organization allows only customer `C00000000`. The fix is the two project policies on `demo-pr-logging` already in `0-core-projects/main.tf`. Organization policy takes about two minutes to propagate. If the first apply after those policies still returns 412, wait two minutes and apply again. Do not remove the policies.

### Stage 1: 403 resourcemanager.folders.create

```bash
gcloud organizations add-iam-policy-binding 000000000000 \
  --member="user:operator@example.com" \
  --role="roles/resourcemanager.folderAdmin"
```

Then `terraform apply` again. Folders created before the error are already in state.

### Stage 1: 400 Group does not exist

The email in `1-org/terraform.tfvars` is not the email in the Groups console. Edit tfvars to the console email and apply again. Do not add `google_cloud_identity_group` back.

### Stage 1: 409 POLICY_ALREADY_EXISTS

Google already has that policy as a baseline. Do not import `iam.disableServiceAccountKeyUpload`, `iam.allowedPolicyMemberDomains`, `iam.automaticIamGrantsForDefaultServiceAccounts`, or `storage.uniformBucketLevelAccess`. They are intentionally absent from this configuration. If one of them is still in state from an earlier import, remove it from state without deleting it in GCP:

```bash
cd 1-org
terraform state rm 'module.organization.google_org_policy_policy.default["iam.allowedPolicyMemberDomains"]'
```

Repeat for each baseline constraint that is still in state. Then apply. `state rm` forgets the object. It does not delete the live policy. `terraform destroy` would.

### Stage 1: 404 on run.requireInvokerIam

The constraint is not on this organization. It is not in the configuration. Leave it out.

### Stage 3: Cloud billing quota exceeded

The project may already exist with no billing account. `demo-pr-prod-bu-0` did. Unlink `example-extra-project` ([section 5](#5-billing-quota)).

If the failed apply left the project tainted, the next plan says `1 to destroy` and then fails with `Cannot destroy project as deletion_policy is set to PREVENT`. The project is still in GCP. Clear the taint and apply. Approve only a plan that says `0 to destroy`:

```bash
cd 4-workload-projects
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform untaint 'module.project["business-unit-0-prod"].google_project.project[0]'
terraform plan -out=tfplan
terraform apply tfplan
```

If untaint reports that the resource is not in state, the create never saved it, but the project exists. Import it, then plan:

```bash
terraform import 'module.project["business-unit-0-prod"].google_project.project[0]' demo-pr-prod-bu-0
terraform plan -out=tfplan
```

Stop if that plan still wants to destroy the project. Do not type `yes`.

### Plan wants to destroy a project or a folder

Type anything other than `yes`. Inspect the plan. Projects and folders in this repository are protected against delete, so the apply will error and leave a tainted or half-updated state. Fix the plan until destroy is 0.

## 11. Check the result

Stage 0:

```bash
cd 0-core-projects
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform output
gcloud projects describe demo-pr-iac-core --format='value(projectId,lifecycleState)'
gcloud storage buckets describe gs://demo-pr-tfstate-bootstrap --format='value(name,location)'
```

Stage 1:

```bash
cd ../1-org
terraform output folder_ids
terraform output org_policies_enforced
```

`org_policies_enforced` includes the YAML policies (`compute.requireOsLogin`, `iam.disableServiceAccountKeyCreation`, and the rest) and the two variable policies. It does not include the four baseline policies.

Stage 2:

```bash
cd ../3-cicd-identity
terraform output workload_identity_provider_name
```

Stage 3:

```bash
cd ../4-workload-projects
terraform output projects
gcloud billing projects describe demo-pr-prod-bu-0 --format='value(billingAccountName)'
gcloud billing projects describe demo-np-nonprod-bu-0 --format='value(billingAccountName)'
```

Both billing descriptions must be `billingAccounts/000000-000000-000000`.

Console check: the resource hierarchy shows `demo-np-nonprod-bu-0` under Workloads / Business Unit 0 / Non-Prod and `demo-pr-prod-bu-0` under Prod.

## 12. After the stages

These are not Terraform applies. They are what turns the pool into a pipeline. Details and the variable table are in the [repository README](../README.md).

1. In `<github-org>/gcp-foundation-bootstrap` and `<github-org>/gcp-infrastructure-lz`, set Actions variable `WIF_PROVIDER` to the stage 2 output `workload_identity_provider_name`.
2. Set `TF_SA` to the stage 0 output `automation_service_accounts.execute`. Set `TF_STATE_BUCKET` from `state_buckets`. Use that same `TF_SA` email in the landing-zone repository.
3. Create the `production` environment with required reviewers and deployment limited to `main`.
4. Apply the branch ruleset. `make protect` does that when `gh` is authenticated.
5. Remove `user:operator@example.com` from `roles/owner` on `demo-pr-iac-core`, `demo-pr-billing`, and `demo-pr-logging` only after a GitHub apply has succeeded. The creator of a project is Owner until that binding is removed.
6. Remove the temporary organization roles from [section 3](#3-roles-to-grant-before-the-first-apply) on the same condition. `dev-terraform-execute` already has the organization roles it needs.

`gcp-infrastructure-lz` is the next repository, and only after `2-network-projects` has been applied. The hub stage no longer takes a billing account or the bootstrap state bucket. The spoke stage no longer takes a billing account. The CIDRs stay: hub `10.0.0.0/24`, prod `10.16.0.0/12`, nonprod `10.32.0.0/12`.

## 13. Rules for every session

- Export a fresh access token at the start of the session and again after an hour.
- Pass `-backend-config="bucket=demo-pr-tfstate-bootstrap"` on init. Do not type the bucket into `backend.tf`.
- Run stages in the order in `config/stages.txt`. `4-workload-projects` fails if `1-org` state or the identity state at `bootstrap/2-cicd-identity` is missing. `2-network-projects` fails if `1-org` state is missing.
- Read the plan. Continue only when destroy is 0.
- Re-apply after a partial failure. Successful resources are already in state.
- Keep `github_org` set to the GitHub organization name in stages 2 and 3.
- Keep group emails identical to the Groups console.
- Do not import Google's four baseline organization policies.
- Do not destroy, and do not unlock retention on the audit bucket or the access-log bucket. Both locks are off and irreversible once enabled.
