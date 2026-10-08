# Search starts in Postgres; pgvector only after a measured need; no Pinecone

Status: accepted (2026-10-07).

Jon asked whether he needs "pinecone vector database or whatever" (Studio addendum, OBSERVED). Scoring, replay,
sync and editing need no vectors at all. Search over lesson notes, cues and clip descriptions starts as ordinary
Postgres full-text search, under the same RLS as everything else (ADR-0018).

Embeddings are added only once a measured retrieval need exists. When they are, they use **Supabase pgvector** in
the same database:

- vectors of up to 2,000 dimensions with an HNSW index;
- iterative index scans, so RLS-filtered queries still return enough rows;
- the same RLS as the lesson rows they point at.

A user's search therefore cannot reach another user's clips, and deleting a lesson removes its vectors in the same
transaction.

## Considered Options

- **Pinecone.** Rejected. It is a second tenant-isolation boundary outside Postgres: permissions would have to be
  mirrored into metadata filters and kept in sync, deletes would have to be propagated, and it adds another vendor,
  bill and secret. At JOVRA's data sizes (hundreds of sessions per user) pgvector is ample.
- **Embeddings from day one.** Rejected. It means a cost and an extra model call with no measured benefit.

## Consequences

The planner's evidence retrieval (ADR-0016) reads authorized rows by ID and filter, not by similarity. Adding pgvector
later is a migration plus a backfill job.

Sources: https://supabase.com/docs/guides/ai/rag-with-permissions ;
https://supabase.com/docs/guides/database/extensions/pgvector ; https://github.com/pgvector/pgvector ;
`docs/research/studio/backend-architecture.md` §5.
