locals {
  api_gateway_wildcard_operations = [
    { method = "get", operation_id = "wildcardGet" },
    { method = "post", operation_id = "wildcardPost" },
    { method = "put", operation_id = "wildcardPut" },
    { method = "patch", operation_id = "wildcardPatch" },
    { method = "delete", operation_id = "wildcardDelete" },
    { method = "options", operation_id = "wildcardOptions" },
  ]
}

resource "google_api_gateway_api" "mcart" {
  provider = google-beta
  count    = var.enable_api_gateway ? 1 : 0
  api_id   = var.api_gateway_api_id

  depends_on = [google_project_service.required]
}

resource "google_api_gateway_api_config" "mcart" {
  provider = google-beta
  count    = var.enable_api_gateway ? 1 : 0

  api           = google_api_gateway_api.mcart[0].id
  api_config_id = var.api_gateway_config_id

  openapi_documents {
    document {
      path     = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi/mcart-gateway.yaml.tftpl", {
        backend_base_url     = var.ingress_https_backend_base_url
        disable_auth         = var.api_gateway_backend_disable_auth
        gateway_operations   = local.api_gateway_wildcard_operations
      }))
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_api_gateway_api.mcart]
}

resource "google_api_gateway_gateway" "mcart" {
  provider = google-beta
  count    = var.enable_api_gateway ? 1 : 0

  region     = var.region
  gateway_id = var.api_gateway_id
  api_config = google_api_gateway_api_config.mcart[0].id

  depends_on = [google_api_gateway_api_config.mcart]
}

resource "google_compute_region_network_endpoint_group" "mcart_apigw" {
  provider = google-beta
  count    = local.apigw_https_lb ? 1 : 0

  name                  = "mcart-apigw-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  serverless_deployment {
    platform = "apigateway.googleapis.com"
    resource = google_api_gateway_gateway.mcart[0].id
  }

  depends_on = [google_api_gateway_gateway.mcart]
}

resource "google_compute_backend_service" "mcart_apigw" {
  count = local.apigw_https_lb ? 1 : 0

  name                  = "mcart-apigw-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = false

  backend {
    group = google_compute_region_network_endpoint_group.mcart_apigw[0].id
  }
}

resource "google_compute_managed_ssl_certificate" "mcart" {
  count = local.apigw_https_lb ? 1 : 0

  name = "mcart-apigw-cert"

  managed {
    domains = distinct(compact(concat([var.domain_name], var.domain_aliases)))
  }
}

resource "google_compute_url_map" "mcart_apigw" {
  count = local.apigw_https_lb ? 1 : 0

  name            = "mcart-apigw-urlmap"
  default_service = google_compute_backend_service.mcart_apigw[0].id
}

resource "google_compute_target_https_proxy" "mcart_apigw" {
  count = local.apigw_https_lb ? 1 : 0

  name             = "mcart-apigw-https-proxy"
  url_map          = google_compute_url_map.mcart_apigw[0].id
  ssl_certificates = [google_compute_managed_ssl_certificate.mcart[0].id]
}

resource "google_compute_global_forwarding_rule" "mcart_apigw_https" {
  count = local.apigw_https_lb ? 1 : 0

  name                  = "mcart-apigw-https"
  target                = google_compute_target_https_proxy.mcart_apigw[0].id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.mcart_public[0].id
}
