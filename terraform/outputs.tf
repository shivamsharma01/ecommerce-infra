output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.main.name
}

output "subnet_name" {
  description = "GKE subnet name."
  value       = google_compute_subnetwork.gke.name
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "Cluster region or zone."
  value       = google_container_cluster.primary.location
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (sensitive)."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64, sensitive)."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  description = "Service account used by node pools (bind workloads via Workload Identity separately)."
  value       = google_service_account.gke_nodes.email
}

output "kubectl_context_hint" {
  description = "Example gcloud command to fetch credentials."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --location ${google_container_cluster.primary.location} --project ${var.project_id}"
}

output "mcart_static_ip_address" {
  description = "Global IPv4 for DNS: apex and www A records → this address (public HTTPS LB on GKE Ingress)."
  value       = google_compute_global_address.mcart_public.address
}

output "cloud_dns_zone_name_servers" {
  description = "Delegate your registrar to these NS records when create_cloud_dns_public_zone is true."
  value       = try(google_dns_managed_zone.public[0].name_servers, null)
}

output "catalog_images_bucket_name" {
  description = "GCS bucket used by demo catalog product images."
  value       = google_storage_bucket.catalog_images.name
}

output "catalog_images_public_base_url" {
  description = "Public base URL prefix for objects when catalog_images_bucket_public is true."
  value       = "https://storage.googleapis.com/${google_storage_bucket.catalog_images.name}"
}

output "public_https_url" {
  description = "Browser origin once DNS points at mcart_static_ip_address (https://var.domain_name)."
  value       = "https://${var.domain_name}"
}
