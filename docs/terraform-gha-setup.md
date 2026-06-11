# Terraform CI — Manual Setup Tasks

One-time setup required before the `Terraform` workflow
(`.github/workflows/terraform.yml`) can run. Implements
[ADR 0001](adrs/0001-terraform-workspaces-in-github-actions.md).

Work through these in order — later steps depend on earlier ones.

## 1. Enable versioning on the state bucket

The `bruner-infra` bucket is not Terraform-managed, so this is a one-off
command (makes state recoverable if a bad write ever happens):

```bash
gcloud storage buckets update gs://bruner-infra --versioning
```

## 2. Bootstrap GCP CI identity (apply `clouds/gcp/iam` locally)

CI cannot grant itself its own permissions, so the first apply of the new
`gha-terraform.tf` resources must happen locally:

```bash
gcloud auth application-default login
cd terraform/clouds/gcp/iam
terraform init && terraform apply
terraform output  # note the two gha_terraform_* values
```

## 3. Bootstrap AWS CI identity (apply `clouds/aws/notifications` locally)

```bash
# Use whatever local AWS credentials you normally use for this account
cd terraform/clouds/aws/notifications
terraform init && terraform apply
terraform output gha_terraform_role_arn
```

> If the AWS account already has a GitHub OIDC provider
> (`token.actions.githubusercontent.com`), the apply will fail with
> `EntityAlreadyExists` — import it instead:
> `terraform import aws_iam_openid_connect_provider.github <provider-arn>`

## 4. Set GitHub Actions variables

Repository → Settings → Secrets and variables → Actions → **Variables**
(or `gh variable set ...`):

| Variable | Value |
|----------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `gha_terraform_workload_identity_provider` output from step 2 (`projects/<num>/locations/global/workloadIdentityPools/github-actions/providers/github-provider`) |
| `GCP_TERRAFORM_SERVICE_ACCOUNT` | `gha_terraform_service_account_email` output from step 2 (`svc-gha-terraform@<project>.iam.gserviceaccount.com`) |
| `AWS_TERRAFORM_ROLE_ARN` | `gha_terraform_role_arn` output from step 3 |
| `AWS_REGION` | `us-east-1` (optional — this is the fallback default) |

## 5. Create the `production` GitHub environment

Repository → Settings → Environments → New environment → `production`.

No required reviewers are needed initially (per ADR 0001), but this is
where to add a manual approval gate later for sensitive workspaces.

## 6. Per-workspace tfvars secrets

Each workspace's gitignored `terraform.tfvars` becomes a **repository
secret** named `TFVARS_<KEY>`, where `<KEY>` is the workspace path under
`terraform/`, uppercased, with non-alphanumerics replaced by `_`. CI writes
the secret's content to `ci.auto.tfvars` before plan/apply. They must be
repository-level (not environment-scoped) secrets because PR plans need
provider credentials too.

From a machine that has the local tfvars files:

```bash
gh secret set TFVARS_<KEY> < terraform/<workspace>/terraform.tfvars
```

Required secrets and their contents:

| Secret | Workspace | Must contain |
|--------|-----------|--------------|
| `TFVARS_CLOUDS_GCP_IAM` | `clouds/gcp/iam` | `project_id` |
| `TFVARS_CLOUDS_GCP_BRUNER_FAMILY` | `clouds/gcp/bruner.family` | `project_id` |
| `TFVARS_CLOUDS_GCP_COLINBRUNER_COM` | `clouds/gcp/colinbruner.com` | `project_id` |
| `TFVARS_CLOUDS_GCP_AUTH_COLINBRUNER_COM` | `clouds/gcp/auth.colinbruner.com` | `project_id`, `iap_user`, `pocket_id_app_url`, `cloudflare_api_token`, `cloudflare_account_id`, `cloudflare_zone_id`, `cloudflare_tunnel_hostname` |
| `TFVARS_CLOUDS_CLOUDFLARE_ZERO_TRUST` | `clouds/cloudflare/zero-trust` | `cloudflare_api_token`, `cloudflare_account_id`, `cloudflare_team_name`, `pocket_id_app_url`, `client_id`, `client_secret`, `cloudflare_zone_id`, `cloudflare_domain`, ... |
| `TFVARS_PLATFORMS_SUPABASE` | `platforms/supabase` | `access_token`, `organization_id`, `database_password`, OIDC vars |

No secrets needed: `clouds/gcp/backups`, `clouds/gcp/unas-backups` (no
variables), `clouds/aws/notifications` (all variables have defaults).

1Password stays the source of truth for the credentials inside these files;
the GitHub secrets are a synced copy. Re-run `gh secret set` after rotating
anything.

## 7. Smoke test

1. Open a PR that touches one low-risk workspace (e.g. a comment change in
   `terraform/clouds/gcp/iam/`) — confirm the plan comment appears and shows
   no unexpected diff.
2. Merge — confirm the apply job runs under the `production` environment
   and succeeds.

## Maintenance notes

- **New workspace**: create the directory with a `backend.tf` (it gets
  discovered automatically) and, if it has required variables, add its
  `TFVARS_<KEY>` secret.
- **Terraform version bump**: edit `terraform/.terraform-version`.
- **CI missing a GCP permission**: extend the role list in
  `terraform/clouds/gcp/iam/gha-terraform.tf`.
- **Stuck state lock** (e.g. a cancelled run): CI never force-unlocks;
  inspect and clear manually with
  `terraform -chdir=<workspace> force-unlock <lock-id>`.
