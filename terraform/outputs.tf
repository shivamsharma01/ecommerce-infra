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

output "workload_service_account_emails" {
  description = "GCP emails for microservice Workload Identity when create_workload_service_accounts is true; null otherwise (set workload_service_accounts in tfvars yourself)."
  value = var.create_workload_service_accounts ? {
    auth            = google_service_account.workload_auth[0].email
    user            = google_service_account.workload_user[0].email
    product         = google_service_account.workload_product[0].email
    product_indexer = google_service_account.workload_product_indexer[0].email
  } : null
}

output "kubectl_context_hint" {
  description = "Example gcloud command to fetch credentials."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --location ${google_container_cluster.primary.location} --project ${var.project_id}"
}

output "mcart_static_ip_address" {
  description = "Global IPv4 for DNS: apex and www A records → this address (public HTTPS LB on GKE Ingress)."
  value       = google_compute_global_address.mcart_public.address
}

output "mcart_gateway_static_ip_address" {
  description = "Regional IPv4 reserved for the Envoy Gateway Service type LoadBalancer (single public entrypoint)."
  value       = google_compute_address.mcart_gateway.address
}

output "cloud_dns_zone_name_servers" {
  description = "Delegate your registrar to these NS records when create_cloud_dns_public_zone is true."
  value       = try(google_dns_managed_zone.public[0].name_servers, null)
}

output "catalog_images_bucket_name" {
  description = "GCS bucket used by catalog product images (set CATALOG_IMAGES_BUCKET in the product service to this exact name)."
  value       = data.google_storage_bucket.catalog_images.name
}

output "catalog_images_public_base_url" {
  description = "Public base URL prefix for catalog image objects."
  value       = "https://storage.googleapis.com/${data.google_storage_bucket.catalog_images.name}"
}

output "product_pubsub_health_subscription" {
  description = "Pub/Sub subscription id for Spring PubSubHealthIndicator (SPRING_CLOUD_GCP_PUBSUB_HEALTH_SUBSCRIPTION)."
  value       = try(google_pubsub_subscription.product_pubsub_health[0].name, null)
}

output "public_https_url" {
  description = "Browser origin once DNS points at mcart_static_ip_address (https://var.domain_name)."
  value       = "https://${var.domain_name}"
}
