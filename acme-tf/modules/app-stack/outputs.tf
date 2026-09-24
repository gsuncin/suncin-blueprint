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

# Re-exported so the shell-level checks can read the SAME text that lands on
# the box, from a directory that needs no credentials and no state backend:
#
#   terraform -chdir=acme-tf/tests/render output -raw compose_file > /tmp/c.yml
#   .github/scripts/check-deploy-contract.sh /tmp/c.yml
#
# Deliberately NOT sensitive, and that is enforcement rather than a label: the
# production compose file carries no secret — every container reads one 0600
# env file that the bootstrap writes — so the moment a secret is interpolated
# into the template this output becomes unreadable by `terraform output -raw`
# and the render tests go red.
output "compose_file" {
  description = "Rendered /opt/<project>/docker-compose.yml. Secrets live in the env files it references, never in the file itself."
  value       = local.compose_file
}
