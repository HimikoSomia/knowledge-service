# ADR 0005: Manual workspace knowledge sources

- Status: Accepted for Phase 08
- Date: 2026-08-25

## Context

Phase 07 grounded answers only in processed document chunks, although its retrieval result contract was deliberately source-neutral. Workspaces also need user-authored context such as decisions, reminders, project facts, and working notes. Git repositories and project systems are future sources, but they require credential storage, sync scheduling, path and content allowlists, deletion behavior, and external identity policies that manual text does not require.

Introducing collection, entry, connector, and synchronization layers before a real multi-entry external source exists would add speculative architecture. Phase 08 therefore establishes the smallest source-neutral persistence and retrieval path needed by current behavior.

## Decision

Phase 08 adds user-authored notes and memos as first-class workspace knowledge:

- `KnowledgeSource` belongs to both one authenticated user and one of that user's workspaces. It stores one note or memo as titled text.
- `KnowledgeChunk` stores searchable chunks and 1,536-dimension embeddings for a knowledge source. Existing document chunks remain unchanged.
- Note and memo create, edit, and delete operations are nested beneath an owned workspace and derive `user_id` from `Current.user`.
- `IndexKnowledgeSourceJob` splits and embeds text outside the request cycle. Persisted generation and job claims reject duplicate delivery and stale results after an edit.
- Indexing states are `pending`, `indexing`, `ready`, `unindexed`, and `failed`. Missing embedding configuration preserves the source as `unindexed`; transient provider failures retry; terminal failures store only a safe error code.
- Re-indexing replaces chunks only after the current generation receives complete embeddings. Non-ready sources are excluded from retrieval.
- `Retrieval::WorkspaceKnowledgeSearchService` embeds a query once, performs separately ownership-scoped document and manual-source vector queries, and merges their candidates by distance.
- Both grounded Q&A and direct passage search use the combined source search. The existing answer provider continues to receive only source-neutral retrieval results.
- Answer citations remain snapshots. Deleting or editing a source does not rewrite prior question history.

Phase 08 does not add a separate `KnowledgeEntry` model. Current manual sources contain one body of text, so a source-to-entry layer would not yet represent a real distinction. A future Git or project integration may introduce entries when one source genuinely contains many independently identified records.

## HTML semantics

| Operation | Outcome |
| --- | --- |
| `GET /workspaces/:workspace_id/knowledge_sources/new` | Renders the owned note/memo form. |
| `POST /workspaces/:workspace_id/knowledge_sources` | Saves an owned source and queues indexing. |
| `GET /workspaces/:workspace_id/knowledge_sources/:id/edit` | Renders an owned source for editing. |
| `PATCH /workspaces/:workspace_id/knowledge_sources/:id` | Updates the source and queues a new indexing generation. |
| `DELETE /workspaces/:workspace_id/knowledge_sources/:id` | Deletes the owned source and its chunks. |
| Blank, oversized, or unsupported input | `422 Unprocessable Entity`. |
| Missing or cross-user workspace/source | `404 Not Found`. |

Phase 08 does not add a new public or token-authenticated API. The grounded question JSON API continues returning note and memo citation snapshots when those sources support an answer.

## Deferred integrations

Git repositories and project systems require separate decisions covering:

- Provider authentication and encrypted credential storage.
- Repository, branch, path, file-type, and record allowlists.
- Initial import, incremental sync, rate limiting, retries, and stale external objects.
- Source deletion, provider revocation, and retention of citation history.
- Secret scanning and exclusion of generated, binary, vendored, or oversized content.

They must not be added by treating arbitrary external payloads as trusted manual notes.

## Verification requirements

- Model and database coverage for validation, ownership, associations, enums, constraints, and dependent deletion.
- Controller coverage for successful CRUD, validation failures, derived ownership, and two-user isolation.
- Job coverage for success, missing configuration, duplicate delivery, stale generation, transient retry, and safe terminal failure.
- Retrieval coverage for one query embedding, document/manual merging, status filtering, workspace boundaries, and two-user isolation.
- Existing document chunking, grounded Q&A, and direct search behavior remain covered without live provider calls.
