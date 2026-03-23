# Optional: run `make validate` before `terraform plan` / `apply`.
# If `terraform` is not installed, use Docker (same image as CI can use):
#   make validate-docker

.PHONY: validate validate-docker fmt apis-enable apis-verify

# One-time per project: enable GCP APIs (requires Owner or Service Usage Admin on gcloud).
# Example: make apis-enable PROJECT_ID=ecommerce-491019
apis-enable:
	@test -n "$(PROJECT_ID)" || (echo "Set PROJECT_ID=your-gcp-project"; exit 1)
	bash scripts/enable-apis.sh "$(PROJECT_ID)"

apis-verify:
	@test -n "$(PROJECT_ID)" || (echo "Set PROJECT_ID=your-gcp-project"; exit 1)
	bash scripts/verify-apis.sh "$(PROJECT_ID)"

validate:
	terraform init -backend=false -input=false
	terraform validate

validate-docker:
	docker run --rm --entrypoint /bin/sh \
		-v "$$(pwd):/workspace" -w /workspace \
		hashicorp/terraform:1.9 \
		-c 'terraform init -backend=false -input=false && terraform validate'

fmt:
	terraform fmt -recursive .
