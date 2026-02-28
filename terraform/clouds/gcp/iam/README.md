# IAM Terraform README

This directory contains the Terraform configuration for GCP IAM resources
(service accounts, IAM bindings, etc.). The examples below cover the
typical workflow and how to inspect the values that Terraform exports.

## Prerequisites

- [Terraform](https://www.terraform.io) 1.x installed.
- A Google Cloud SDK account authenticated (`gcloud auth application-default login`).
- The `project_id` variable set via `terraform.tfvars`, `-var`, or
  `TF_VAR_project_id` environment variable.
