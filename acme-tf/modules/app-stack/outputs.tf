output "cloud_init" {
  description = "Rendered cloud-config. Contains every secret in plaintext — it is metadata on the instance and it lands in Terraform state, which is why the state backend must be private and encrypted."
  value       = local.cloud_init
  sensitive   = true
}

output "cloud_init_gzipped" {
  description = "base64gzip of the above. Required: the rendered file exceeds the 32 KB instance-metadata limit on most providers, and the failure is a confusing API error rather than a size complaint."
  value       = base64gzip(local.cloud_init)
  sensitive   = true
}

output "install_dir" {
  value = "/opt/${var.project}"
}
