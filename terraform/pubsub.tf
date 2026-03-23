resource "google_pubsub_topic" "product_events" {
  name = "product-events"
}

resource "google_pubsub_subscription" "product_events_sub" {
  name  = "product-events-sub"
  topic = google_pubsub_topic.product_events.name

  ack_deadline_seconds = 60

  depends_on = [google_pubsub_topic.product_events]
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
