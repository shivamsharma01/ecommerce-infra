resource "google_pubsub_topic" "product_events" {
  name = "product-events"
}

resource "google_pubsub_subscription" "product_events_sub" {
  name  = "product-events-sub"
  topic = google_pubsub_topic.product_events.name

  ack_deadline_seconds = 60

  depends_on = [google_pubsub_topic.product_events]
}

resource "google_pubsub_subscription" "inventory_product_events_sub" {
  name  = "inventory-product-events-sub"
  topic = google_pubsub_topic.product_events.name

  ack_deadline_seconds = 60

  depends_on = [google_pubsub_topic.product_events]
}

resource "google_pubsub_topic" "order_paid_events" {
  name = "order-paid-events"
}

resource "google_pubsub_subscription" "order_paid_email_sub" {
  name  = "order-paid-email-sub"
  topic = google_pubsub_topic.order_paid_events.name

  ack_deadline_seconds = 120

  depends_on = [google_pubsub_topic.order_paid_events]
}

resource "google_pubsub_topic" "user_signup_events" {
  name = "user-signup-events"
}

resource "google_pubsub_subscription" "user_signup_events_sub" {
  name  = "user-signup-events-sub"
  topic = google_pubsub_topic.user_signup_events.name

  ack_deadline_seconds = 60

  depends_on = [google_pubsub_topic.user_signup_events]
}

resource "google_pubsub_topic" "email_verification_events" {
  name = "email-verification-events"
}

resource "google_pubsub_subscription" "email_verification_events_sub" {
  name  = "email-verification-events-sub"
  topic = google_pubsub_topic.email_verification_events.name

  ack_deadline_seconds = 120

  depends_on = [google_pubsub_topic.email_verification_events]
}

# Dedicated topic/subscription with no publishers: Spring Cloud GCP PubSubHealthIndicator pulls here
# so the product SA only needs subscriber on this subscription (not on product-events-sub).
resource "google_pubsub_topic" "product_pubsub_health" {
  count = var.enable_product_pubsub_health_resources ? 1 : 0
  name  = "mcart-product-pubsub-health"
}

resource "google_pubsub_subscription" "product_pubsub_health" {
  count = var.enable_product_pubsub_health_resources ? 1 : 0

  name  = "mcart-product-pubsub-health-sub"
  topic = google_pubsub_topic.product_pubsub_health[0].name

  ack_deadline_seconds       = 10
  message_retention_duration = "600s"

  depends_on = [google_pubsub_topic.product_pubsub_health]
}
