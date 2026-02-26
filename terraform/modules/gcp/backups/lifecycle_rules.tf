
locals {
  ###
  # Rules
  ###
  # Delete noncurrent object versions after 10 days
  lifecycle_rule_noncurrent_objects_delete = {
    action = {
      type = "Delete"
    }
    condition = {
      days_since_noncurrent_time = 10
    }
  }

  # Storage Class transition
  # only applied when autoclass != true
  lifecycle_rules_storage_class = [
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition = {
        age = 30
      }
    },
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition = {
        age = 60
      }
    },
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "ARCHIVE"
      }
      condition = {
        age = 180
      }
    }
  ]

  ###
  # Defaults
  ###
  default_lifecycle_rules = [
    local.lifecycle_rule_noncurrent_objects_delete
  ]
  autoclass_disabled_lifecycle_rules = concat(
    local.default_lifecycle_rules,
    local.lifecycle_rules_storage_class
  )

  lifecycle_rules = var.autoclass ? local.default_lifecycle_rules : local.autoclass_disabled_lifecycle_rules


}
