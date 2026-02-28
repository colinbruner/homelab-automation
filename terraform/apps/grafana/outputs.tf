output "gcp_logging_datasource_uid" {
  description = "Grafana UID of the GCP Cloud Logging data source — use this when building dashboards or alerts that reference it"
  value       = grafana_data_source.gcp_logging.uid
}
