# GCP APIs are enabled outside Terraform via scripts/enable-apis.sh (run once as Project Owner).
#
# We do not use google_project_service here: the identity running terraform apply often lacks
# serviceusage.services.list / .enable (403 AUTH_PERMISSION_DENIED). Enabling APIs with
# gcloud as a privileged user avoids that bootstrap loop; terraform then creates resources only.
