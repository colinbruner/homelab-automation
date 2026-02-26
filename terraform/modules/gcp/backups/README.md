# Get Credentials

```bash
# Email
terraform output -json backups_service_account | jq -r ".email" | pbcopy

# JSON Key
terraform output -json backups_service_account | jq -r ".key" | pbcopy
```
