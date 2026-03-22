check "api_gateway_lb_requires_gateway" {
  assert {
    condition     = !var.enable_api_gateway_https_load_balancer || var.enable_api_gateway
    error_message = "enable_api_gateway_https_load_balancer requires enable_api_gateway = true."
  }
}

check "kubernetes_api_network_restriction" {
  assert {
    condition = (
      var.enable_private_endpoint
      || length(var.master_authorized_networks) > 0
      || var.allow_unrestricted_kubernetes_api
    )
    error_message = "Public Kubernetes API with empty master_authorized_networks: set allow_unrestricted_kubernetes_api = true (explicit opt-in) or add master_authorized_networks / enable_private_endpoint."
  }
}

check "node_pool_bounds" {
  assert {
    condition     = var.node_min_count <= var.node_max_count
    error_message = "node_min_count must be less than or equal to node_max_count."
  }
}
