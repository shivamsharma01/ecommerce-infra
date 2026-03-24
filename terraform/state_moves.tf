# Preserve state when upgrading from count-based resources (optional flags removed).
moved {
  from = google_compute_global_address.mcart_public[0]
  to   = google_compute_global_address.mcart_public
}
