# Common bottlenecks

| Area | Pattern | Fix |
|---|---|---|
| **DB** | N+1 query, missing index, `SELECT *`, table scan | eager/batch loading, index (db-migration), only needed columns |
| **Memory** | needless allocation, holding large objects, leak | pooling, streaming, releasing references |
| **Async** | wrong sync/async boundary, blocking I/O, serial await | parallel await, non-blocking I/O |
| **Network/payload** | oversized response, no compression, chatty API | pagination, field selection, gzip, batch (api-design) |
| **Cache** | repeated expensive computation, no/wrong cache | cache at the right layer + correct invalidation |
| **Frontend** | needless render, large bundle, blocking resource | memo, code-split, lazy, critical CSS |
