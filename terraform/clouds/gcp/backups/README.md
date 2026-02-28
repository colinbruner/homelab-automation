# Get Credentials

```bash
# Email
terraform output -json backups_service_account | jq -r ".email" | pbcopy

# JSON Key
terraform output -json backups_service_account | jq -r ".key" | pbcopy
```

# TODO

Investigate bruner-backups. This was likely the first iteration of kopia remote backup for UNAS and is now superceded by unas-backups workspace.
