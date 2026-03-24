# Global IPv4 reserved for the GKE Ingress external HTTP(S) load balancer.
# Set Ingress annotation `kubernetes.io/ingress.global-static-ip-name` to var.static_ip_name.
resource "google_compute_global_address" "mcart_public" {
  name = var.static_ip_name
}

resource "google_dns_managed_zone" "public" {
  count = var.create_cloud_dns_public_zone ? 1 : 0

  name        = var.cloud_dns_zone_name
  dns_name    = "${var.domain_name}."
  description = "Public DNS for ${var.domain_name}"
}

resource "google_dns_record_set" "apex_a" {
  count = var.create_cloud_dns_public_zone ? 1 : 0

  name         = google_dns_managed_zone.public[0].dns_name
  managed_zone = google_dns_managed_zone.public[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.mcart_public.address]
}

resource "google_dns_record_set" "alias_a" {
  for_each = var.create_cloud_dns_public_zone ? toset(var.domain_aliases) : toset([])

  name         = "${each.value}."
  managed_zone = google_dns_managed_zone.public[0].name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.mcart_public.address]
}
