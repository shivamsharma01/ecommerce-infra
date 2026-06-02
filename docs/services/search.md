# search service

Read-only product search against **OpenSearch** index `products`. Does not own catalog writes (see product-indexer).

## 1. Technology and main libraries

| Area | Choice |
|------|--------|
| Runtime | Java 17 |
| Framework | Spring Boot 4.0.2 |
| API | Spring Web (MVC) |
| Search | OpenSearch Java client / REST |
| Security | Optional JWT (`app.security.enabled`); gateway often allows **public POST** search |
| Other | Actuator |

Default port: **8083**. **No Redis.**

## 2. APIs

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/search` | Public at gateway | Full-text / filtered search |
| GET | `/actuator/health/**` | Public | Health |

Request body typically includes query string, pagination, optional filters (category, price range — per DTO).

## 3. Main flows

### Search request

1. Parse and validate search request body.
2. Build OpenSearch query (match, filters, sort).
3. Execute against index **`products`**.
4. Map hits to `SearchResponse` DTO (ids, titles, prices, snippets).

Index documents are written only by **product-indexer** (and admin reindex).

## 4. How requests are validated

| Layer | Mechanism |
|-------|-----------|
| Body | `@Valid` on search request (query length, page/size bounds) |
| JWT | If security enabled, may require token; gateway public route often skips edge JWT |

Invalid pagination → 400 via exception handler.

## 5. When downstream calls fail

| Downstream | On failure |
|------------|------------|
| **OpenSearch** | Connection/query errors → **503** or 500 with logged cause |
| **Empty index** | Valid 200 with empty results (until indexer catches up) |

No Pub/Sub or Postgres in this service.

## 6. Redis usage

**None** (diagrams may mention cache — not implemented in this codebase path).
