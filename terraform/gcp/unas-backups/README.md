# Get Credentials

```bash
# All Email
terraform output -json secrets | jq -r ".[].service_account.email" | pbcopy

# All JSON Key
terraform output -json secrets | jq -r ".[].service_account.key" | pbcopy
```
