# MCART platform documentation

Tutor-style guides for each repository in this monorepo. Use this index to jump to a service or to the deployment repo.

| Document | What it covers |
|----------|----------------|
| [System overview](./00-system-overview.md) | How services fit together, data stores, events, public edge |
| [ecomm-infra](./ecomm-infra.md) | Terraform, GKE, Helm, gateway, deploy flow |
| [mcart-ui](./mcart-ui.md) | Angular storefront, routes, API usage |
| [ecommerce (diagrams only)](./ecommerce.md) | Architecture / sequence diagrams (not runnable code) |

### Microservices

| Service | Document |
|---------|----------|
| auth | [services/auth.md](./services/auth.md) |
| user | [services/user.md](./services/user.md) |
| email | [services/email.md](./services/email.md) |
| product | [services/product.md](./services/product.md) |
| cart | [services/cart.md](./services/cart.md) |
| inventory | [services/inventory.md](./services/inventory.md) |
| payment | [services/payment.md](./services/payment.md) |
| order | [services/order.md](./services/order.md) |
| search | [services/search.md](./services/search.md) |
| product-indexer | [services/product-indexer.md](./services/product-indexer.md) |

### Operational runbooks (separate from service design)

- [Cloud Shell deployment](../ecomm-infra/CLOUD_SHELL_DEPLOYMENT.md) — full GCP bring-up and teardown
