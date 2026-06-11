output "project_id" {
  description = "Supabase project ID (ref)"
  value       = supabase_project.home.id
}

output "project_url" {
  description = "Supabase project API URL"
  value       = "https://${supabase_project.home.id}.supabase.co"
}
