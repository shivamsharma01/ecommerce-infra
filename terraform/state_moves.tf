# Preserve state when upgrading from count-based resources (optional flags removed).
moved {
  from = google_compute_global_address.mcart_public[0]
  to   = google_compute_global_address.mcart_public
}

moved {
  from = google_api_gateway_api.mcart[0]
  to   = google_api_gateway_api.mcart
}

moved {
  from = google_api_gateway_api_config.mcart[0]
  to   = google_api_gateway_api_config.mcart
}

moved {
  from = google_api_gateway_gateway.mcart[0]
  to   = google_api_gateway_gateway.mcart
}

moved {
  from = google_compute_region_network_endpoint_group.mcart_apigw[0]
  to   = google_compute_region_network_endpoint_group.mcart_apigw
}

moved {
  from = google_compute_backend_service.mcart_apigw[0]
  to   = google_compute_backend_service.mcart_apigw
}

moved {
  from = google_compute_managed_ssl_certificate.mcart[0]
  to   = google_compute_managed_ssl_certificate.mcart
}

moved {
  from = google_compute_url_map.mcart_apigw[0]
  to   = google_compute_url_map.mcart_apigw
}

moved {
  from = google_compute_target_https_proxy.mcart_apigw[0]
  to   = google_compute_target_https_proxy.mcart_apigw
}

moved {
  from = google_compute_global_forwarding_rule.mcart_apigw_https[0]
  to   = google_compute_global_forwarding_rule.mcart_apigw_https
}
