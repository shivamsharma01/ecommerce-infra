variable "project_id" {
  description = "GCP project ID where the cluster will be created."
  type        = string
}

variable "region" {
  description = "GCP region for the cluster and regional resources."
  type        = string
}

variable "zone" {
  description = "GCP zone for zonal node pool (ignored if regional node pool is used)."
  type        = string
  default     = null
}

variable "environment" {
  description = "Short name for labels (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "network_name" {
  description = "Name of the VPC."
  type        = string
  default     = "mcart-vpc"
}

variable "subnet_name" {
  description = "Name of the primary GKE subnet."
  type        = string
  default     = "mcart-gke-subnet"
}

variable "subnet_cidr" {
  description = "Primary IPv4 CIDR for nodes in the GKE subnet."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_range_name" {
  description = "Secondary range name for cluster pod IPs (VPC-native GKE)."
  type        = string
  default     = "mcart-pods"
}

variable "pods_cidr" {
  description = "Secondary CIDR for pods (must not overlap subnet_cidr or services_cidr)."
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_range_name" {
  description = "Secondary range name for cluster service IPs."
  type        = string
  default     = "mcart-services"
}

variable "services_cidr" {
  description = "Secondary CIDR for Kubernetes services."
  type        = string
  default     = "10.8.0.0/20"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "mcart-gke"
}

variable "cluster_version" {
  description = "GKE control plane version (null = channel default / latest stable in channel)."
  type        = string
  default     = null
}

variable "release_channel" {
  description = "GKE release channel: UNSPECIFIED, RAPID, REGULAR, or STABLE."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be UNSPECIFIED, RAPID, REGULAR, or STABLE."
  }
}

variable "master_ipv4_cidr" {
  description = "Private /28 for the control plane endpoint (must not overlap VPC ranges)."
  type        = string
  default     = "172.16.0.0/28"
}

variable "enable_private_endpoint" {
  description = "If true, Kubernetes API is only reachable from VPC/peering (no public API endpoint)."
  type        = bool
  default     = false
}

variable "allow_unrestricted_kubernetes_api" {
  description = <<-EOT
    When false, a public control plane (enable_private_endpoint = false) requires at least one
    master_authorized_networks entry. Set true only if you intentionally accept API-reachable-from-internet
    (still TLS + RBAC). Default true preserves previous apply behavior; set false for stricter prod.
  EOT
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the public control plane endpoint (when private endpoint is false)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "node_machine_type" {
  description = "Machine type for default node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_min_count" {
  description = "Minimum nodes per zone in the default pool."
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum nodes per zone in the default pool."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  description = "Boot disk size (GB) per node."
  type        = number
  default     = 50
}

variable "node_disk_type" {
  description = "Boot disk type (pd-standard is cheaper than pd-balanced for short demos)."
  type        = string
  default     = "pd-standard"
}

variable "node_preemptible" {
  description = "Use preemptible (Spot) VMs for the default node pool — large savings; nodes can be reclaimed anytime (fine for demos)."
  type        = bool
  default     = true
}

variable "regional_cluster" {
  description = "If true, create a regional cluster (3 zones); if false, zonal using var.zone."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect cluster from accidental destroy via Terraform."
  type        = bool
  default     = false
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity on the cluster."
  type        = bool
  default     = true
}

variable "node_service_account_id" {
  description = "Account ID (short name) for the GKE node service account."
  type        = string
  default     = "mcart-gke-nodes"
}

# --- Platform: Pub/Sub, Firestore IAM, DNS --------------------------------------------------------

variable "workload_service_accounts" {
  description = <<-EOT
    GCP service account emails used by microservices (typically via GKE Workload Identity).
    When set, Terraform grants least-privilege Pub/Sub (topic/subscription) and optional Firestore IAM.
    auth: publishes to user-signup-events (auth OutboxPublisherJob).
    user: subscribes to user-signup-events-sub (UserSignupSubscriber).
    product: publishes to product-events + Firestore (product service).
    product_indexer: subscribes to product-events-sub + Firestore reads (product-indexer).
  EOT
  type = object({
    auth            = optional(string)
    user            = optional(string)
    product         = optional(string)
    product_indexer = optional(string)
  })
  default = {}
}

variable "extra_project_iam_members" {
  description = "Additional project-level IAM bindings (e.g. legacy serviceAccount:... with roles/pubsub.publisher)."
  type        = map(list(string))
  default     = {}
}

variable "domain_name" {
  description = "Primary public hostname (no scheme), e.g. mcart.space. Used for managed cert and optional Cloud DNS records."
  type        = string
  default     = "mcart.space"
}

variable "domain_aliases" {
  description = "Extra hostnames for the managed SSL certificate (e.g. www.mcart.space)."
  type        = list(string)
  default     = ["www.mcart.space"]
}

variable "static_ip_name" {
  description = "GCP resource name for the global IPv4 attached to the public HTTPS load balancer (DNS points here)."
  type        = string
  default     = "mcart-public-ip"
}

variable "create_cloud_dns_public_zone" {
  description = "If true, create a Cloud DNS public zone for var.domain_name and A records to the static IP (requires NS delegation at registrar)."
  type        = bool
  default     = false
}

variable "cloud_dns_zone_name" {
  description = "Cloud DNS managed zone name (DNS name is var.domain_name when zone is created)."
  type        = string
  default     = "mcart-public-zone"
}

variable "catalog_images_bucket_name" {
  description = "GCS bucket for demo product images. Null = auto name based on project."
  type        = string
  default     = null
}

variable "catalog_images_bucket_location" {
  description = "Location for demo catalog image bucket."
  type        = string
  default     = "ASIA-SOUTH2"
}

variable "catalog_images_bucket_public" {
  description = "If true, grant allUsers objectViewer on catalog image bucket (demo convenience)."
  type        = bool
  default     = true
}

