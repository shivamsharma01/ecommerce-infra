# Optional: run `make validate` before `terraform plan` / `apply`.
# If `terraform` is not installed, use Docker (same image as CI can use):
#   make validate-docker

.PHONY: validate validate-docker fmt

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
