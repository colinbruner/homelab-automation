# ADR 0001: Running Multiple Terraform Workspaces Safely in GitHub Actions

- **Status**: Accepted
- **Date**: 2026-06-10

## Context

This repository contains multiple independent Terraform root modules under
`terraform/`, spanning several providers:

```
terraform/
├── clouds/
│   ├── aws/notifications
│   ├── cloudflare/zero-trust
│   └── gcp/{auth.colinbruner.com, backups, bruner.family, colinbruner.com, iam, unas-backups}
├── modules/            # shared modules (gcp/backups, aws/ses)
└── platforms/supabase
```

All root modules store state remotely in the **`bruner-infra` GCS bucket**,
with a backend `prefix` that mirrors the directory path (e.g.
`clouds/gcp/backups/`). This holds even for non-GCP workspaces (AWS,
Cloudflare, Supabase) — GCS is the single state backend for everything.

Today Terraform is run locally with `gcloud auth application-default login`
and secrets pulled from 1Password. We want to move plan/apply into GitHub
Actions. That raises the questions this ADR answers:

1. What is a "workspace" and how does CI discover them?
2. How do we prevent two runs from mutating the same state concurrently?
3. How does CI authenticate to GCP (state + resources), AWS, Cloudflare, and
   Supabase without long-lived keys?
4. When do plans run vs. applies, and what review gate sits between them?

A GCP Workload Identity Federation pool for GitHub Actions already exists
(pool `github-actions`, provider `github-provider`, managed in the
`clouds/gcp/colinbruner.com` workspace) with an attribute condition
restricting it to `repository_owner == "colinbruner"`. We should build on it
rather than create a parallel auth path.

## Decision

### 1. A workspace is a directory, not a `terraform workspace`

A **workspace** is any directory under `terraform/` containing a
`backend.tf` with its own GCS prefix. We will **not** use Terraform CLI
workspaces (`terraform workspace new/select`):

- CLI workspaces share one backend configuration and differentiate state only
  by an internal key, which is easy to get wrong in CI (a forgotten
  `workspace select` plans against the wrong environment).
- The directory-per-root-module layout already in this repo makes blast
  radius, ownership, and state location obvious from the path alone.

CI discovers workspaces dynamically — `find terraform -name backend.tf` —
rather than from a hardcoded list, the same pattern `docker-publish.yml`
uses to discover Dockerfiles. Adding a new workspace requires no workflow
changes.

### 2. Only changed workspaces run; shared modules fan out

A single `terraform.yml` workflow uses path filtering to build a job
**matrix** of affected workspaces:

- A change under `terraform/clouds/gcp/backups/**` queues only that
  workspace.
- A change under `terraform/modules/**` queues **every workspace that
  references the changed module** (resolved by grepping `source` references;
  as a simpler initial implementation, queue all workspaces — the matrix is
  small and plans are cheap).
- Matrix jobs run with `fail-fast: false` so one workspace's failure doesn't
  cancel siblings.

### 3. Plan on PR, apply on merge to `main`

- **Pull requests**: `terraform fmt -check`, `validate`, and `plan` for each
  affected workspace. The plan output is posted as a sticky PR comment (one
  comment per workspace, updated in place on new pushes) so review happens in
  the PR, not in workflow logs.
- **Push to `main`**: the same matrix re-plans and applies.

We deliberately **re-plan at apply time** instead of applying a saved plan
artifact from the PR. Saved plans guarantee you apply exactly what was
reviewed, but go stale the moment anything else touches the same state and
add artifact-passing complexity. At this repo's scale (single operator, low
change frequency) a fresh plan plus the concurrency controls below is the
better trade. To catch surprises, the apply job runs
`plan -detailed-exitcode` first and the apply step is wrapped in a GitHub
**Environment** (`production`) — initially without required reviewers, but
giving us a one-click place to add a manual approval gate later if a
workspace warrants it (e.g. `backups`, which manages KMS keys).

### 4. Concurrency: serialize per workspace, never cancel an apply

Two layers prevent concurrent state mutation:

1. **GitHub Actions concurrency groups**, scoped per workspace:

   ```yaml
   concurrency:
     group: terraform-${{ matrix.workspace }}-${{ github.event_name }}
     cancel-in-progress: ${{ github.event_name == 'pull_request' }}
   ```

   PR plans may cancel superseded runs of the same workspace; **applies are
   never cancelled**, only queued. Different workspaces run in parallel
   freely — their state prefixes are disjoint.

2. **GCS native state locking** as the backstop. The `gcs` backend locks via
   a lock object per prefix, which also protects against the case GHA
   concurrency can't see: a human running `terraform apply` locally while CI
   runs. CI must **never** use `-lock=false` or run `force-unlock`
   automatically; a stuck lock is a human decision.

Additionally, **object versioning must be enabled on `bruner-infra`** so any
state corruption is recoverable. This should be verified/codified in
Terraform as part of implementing this ADR.

### 5. Authentication: WIF everywhere a provider supports OIDC

No long-lived cloud keys are stored in GitHub.

- **GCP (state backend + GCP resources)**: extend the existing
  `github-actions` WIF pool with a dedicated service account
  (`svc-gha-terraform`) bound to
  `attribute.repository/colinbruner/homelab-automation`. Every workspace
  needs this identity regardless of target cloud, because state lives in GCS.
  Jobs authenticate via `google-github-actions/auth` with
  `id-token: write` permissions.
- **AWS**: a GitHub OIDC provider + IAM role in the AWS account, assumed via
  `aws-actions/configure-aws-credentials`, trust policy scoped to this repo
  and (for apply) the `main` ref.
- **Cloudflare / Supabase**: these providers use API tokens, not OIDC.
  Each workspace's required variables (tokens included) live in a
  per-workspace repository secret (`TFVARS_<WORKSPACE_KEY>`) holding tfvars
  content, which CI writes to `ci.auto.tfvars` before running. These are
  repository-level rather than `production`-environment-scoped because PR
  plans also need provider credentials to refresh state; the exposure is
  acceptable since fork PRs never receive secrets and this is a
  single-operator repo. 1Password remains the source of truth; GitHub
  secrets are a synced copy.

**Bootstrap note**: the IAM resources that grant CI its access (in
`clouds/gcp/iam` and `clouds/gcp/colinbruner.com`) must be applied locally
once before the workflow can run — CI cannot grant itself its own
permissions. Subsequent IAM changes flow through CI like everything else.

### 6. Toolchain pinning and hygiene

- Terraform version pinned in one place (a `.terraform-version` file at
  `terraform/`, consumed by `hashicorp/setup-terraform`) so local and CI runs
  agree.
- Provider versions remain pinned per workspace in `versions.tf`, with
  `.terraform.lock.hcl` committed for each workspace so CI installs exactly
  the providers that were planned against.
- `terraform fmt -check -recursive` and `terraform validate` run on every PR
  touching `terraform/`, for all workspaces, regardless of the change matrix
  (they're fast and need no credentials beyond init).

### 7. Scheduled drift detection (follow-up, not blocking)

A weekly scheduled run executes `plan -detailed-exitcode` across all
workspaces and opens/updates a GitHub issue when drift is found. This is
explicitly a follow-up: it adds value but is not required to adopt the
plan/apply pipeline safely.

## Consequences

**Positive**

- One workflow handles all current and future workspaces; adding a workspace
  is just adding a directory with a `backend.tf`.
- Per-workspace concurrency groups + GCS locking make concurrent state
  corruption practically impossible, while unrelated workspaces still apply
  in parallel.
- No cloud keys live in GitHub for GCP/AWS; token-based providers are
  environment-scoped.
- Plans are reviewable in the PR itself, replacing "ran it locally, trust
  me".

**Negative / accepted risks**

- Re-planning at apply time means the applied diff can differ from the
  reviewed plan if the world changed between review and merge. Accepted for
  a single-operator repo; mitigated by `-detailed-exitcode` and the option to
  add environment approvals per workspace.
- Local applies remain possible and bypass the PR review path. GCS locking
  prevents corruption but not policy bypass; discipline (and eventually
  tightening the human SA's permissions) is the mitigation.
- The "plan all workspaces on `modules/**` changes" simplification will get
  slower as workspace count grows; revisit with proper dependency resolution
  if matrix runtime becomes annoying.

## Alternatives considered

- **Terraform CLI workspaces** — rejected; see Decision 1. The repo's
  directory convention is already the safer equivalent.
- **Saved plan artifacts applied after merge** — rejected for now in favor of
  re-plan on `main`; see Decision 3. Worth revisiting if multiple
  contributors start merging concurrently.
- **One workflow file per workspace** — rejected; N copies of the same YAML
  drift apart. The discovery + matrix pattern is already proven in this repo
  by `docker-publish.yml`.
- **Terragrunt / Atlantis / Terraform Cloud** — rejected as disproportionate.
  Atlantis needs a hosted server, TFC moves state out of the already-working
  GCS setup, and Terragrunt's DRY benefits don't pay for their indirection at
  ~8 small workspaces.
