locals {
  cluster_location = var.regional_cluster ? var.region : coalesce(var.zone, "${var.region}-a")
  node_locations   = var.regional_cluster ? null : [local.cluster_location]
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = local.cluster_location

  deletion_protection = var.deletion_protection

  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.gke.name

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = (!var.enable_private_endpoint && length(var.master_authorized_networks) > 0) ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  min_master_version = var.cluster_version

  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  enable_shielded_nodes = true

  initial_node_count       = 1
  remove_default_node_pool = true

  depends_on = [
    google_project_iam_member.gke_node_roles,
  ]
}

resource "google_container_node_pool" "primary" {
  name     = "mcart-primary-pool"
  location = local.cluster_location
  cluster  = google_container_cluster.primary.name

  node_locations = local.node_locations

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible     = var.node_preemptible
    machine_type    = var.node_machine_type
    disk_size_gb    = var.node_disk_size_gb
    disk_type       = var.node_disk_type
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = var.enable_workload_identity ? "GKE_METADATA" : "GCE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags = ["gke-node", var.environment]
  }

  depends_on = [
    google_project_iam_member.gke_node_roles,
  ]
}
