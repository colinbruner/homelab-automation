output "project_id" {
  description = "Supabase project ID (ref)"
  value       = supabase_project.appliance_tracker.id
}

output "project_url" {
  description = "Supabase project API URL"
  value       = "https://${supabase_project.appliance_tracker.id}.supabase.co"
}
