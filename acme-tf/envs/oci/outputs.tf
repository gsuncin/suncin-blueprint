output "public_ip" {
  description = "Point the A records for domain_app and domain_apex here. Note that SSH to this address will hang: port 22 is not open to the internet by design."
  value       = oci_core_public_ip.app.ip_address
}

output "dns_records_required" {
  description = "Certificates cannot be issued until these resolve — the HTTP-01 challenge needs the name to reach this box."
  value = {
    (var.domain_app)         = oci_core_public_ip.app.ip_address
    (var.domain_apex)        = oci_core_public_ip.app.ip_address
    "www.${var.domain_apex}" = oci_core_public_ip.app.ip_address
  }
}

output "ssh_hint" {
  description = "SSH arrives over the tailnet, not the public address."
  # nonsensitive() on the emptiness check, not on the key. Whether a tailnet
  # key is configured is not itself a secret, but referencing a sensitive value
  # in any form taints the whole output — and marking this one `sensitive`
  # would hide a hint whose entire purpose is to be read.
  value = var.enable_instance ? (
    nonsensitive(var.tailscale_authkey != "")
    ? "tailscale ssh ubuntu@${var.project}   # or: ssh ubuntu@<tailnet-ip>"
    : "No tailscale_authkey set. Port 22 is closed to the internet; use the provider's serial console."
  ) : "Instance disabled (enable_instance = false)."
}

output "install_dir" {
  value = module.app_stack.install_dir
}
