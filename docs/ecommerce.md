# ecommerce (documentation repo)

This folder holds **architecture artifacts** for the MCART platform (Draw.io diagrams and text sequence files). It is **not runnable application code**.

**Interview prep, diagram analysis, and demo script:** [interview-prep-and-demo.md](./interview-prep-and-demo.md)

## Contents

- **Draw.io** diagrams (system context, deployment, sequences)
- **Sequence diagrams** for signup, checkout, product indexing, etc.
- Cross-references to service boundaries described in [`00-system-overview.md`](./00-system-overview.md)

## How to use it

1. Open `.drawio` files in [diagrams.net](https://app.diagrams.net/) or the Draw.io VS Code extension.
2. Compare diagrams to live code in each microservice repo — diagrams may lag code slightly (e.g. Redis only in auth/email, not search).

## Technology

| Area | Choice |
|------|--------|
| Format | XML (draw.io), Markdown notes if present |
| Runtime | None |

For deployment and operations, use **`ecomm-infra`** and [`CLOUD_SHELL_DEPLOYMENT.md`](../ecomm-infra/CLOUD_SHELL_DEPLOYMENT.md).
