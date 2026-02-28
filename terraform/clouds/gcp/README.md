# GCP

Creation of project using existing Google Account.

## Authentication

```bash
# Login to GCP via local authentication, Terraform currently ran locally via default app creds.
$ gcloud auth application-default login

# export Cloudflare Token via 1Password.
export TF_VAR_cloudflare_api_token=$(op read "op://core/Cloudflare/API Token - Terraform")
```

## Workspaces

### Backups

Creates and manages Backups GCS Bucket and related resources

### colinbruner.com

Creates and manages GCS Buckets, GitHub WLI Auth, etc related to development, deployment, and operation of colinbruner.com static site.
