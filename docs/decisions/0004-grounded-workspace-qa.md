# ADR 0004: Grounded workspace Q&A

- Status: Accepted for Phase 07
- Date: 2026-08-25

## Context

Workspace search currently embeds a query and displays matching document chunks. It does not synthesize an answer, preserve question state, expose a JSON question resource, or provide citations. Future workspace knowledge will include user-authored notes and memos plus synchronized sources such as Git repositories and project systems, so answer generation must not depend directly on `DocumentChunk`.

## Decision

Phase 07 introduces a single-question, asynchronous Q&A lifecycle:

- `WorkspaceQuestion` belongs to both the authenticated user and one of that user's workspaces.
- HTML and JSON clients create and read questions through nested workspace resources.
- `Retrieval::WorkspaceRetriever` maps document chunks into source-neutral results and applies workspace ownership, relevance, source-diversity, result-count, and context-size limits.
- `Answering::OpenAiAnswerService` receives only the question and bounded retrieval results. It instructs the provider to treat sources as untrusted evidence, requires numbered citations, and rejects empty or invented citations.
- `AnswerWorkspaceQuestionJob` prevents duplicate generation through a persisted job claim, retries transient failures, records safe terminal error codes, and records insufficient context without calling the answer provider.
- Citations are persisted as answer-time snapshots so an answer remains understandable if its source later changes. They contain safe source identity, locator, excerpt, rank number, and vector distance.
- Generated answers are outputs, not workspace evidence. They are not indexed automatically. A future explicit user action may save an answer as a note with provenance.

The first JSON surface uses the application's existing authenticated session. External API tokens, CORS, streaming, and multi-turn conversations are not part of Phase 07.

## API semantics

| Operation | Outcome |
| --- | --- |
| `POST /workspaces/:workspace_id/questions` | HTML redirects to the question; JSON returns `202 Accepted` when answer generation is queued. |
| `GET /workspaces/:workspace_id/questions/:id` | Returns the current HTML or JSON question state. |
| `GET /workspaces/:workspace_id/questions` | Returns recent owned questions in HTML or JSON. |
| Blank or oversized question | `422 Unprocessable Entity`. |
| Missing or cross-user workspace/question | `404 Not Found`. |
| Rate limited question creation | `429 Too Many Requests` for JSON. |
| Queue enqueue failure | The question is failed with `queue_unavailable`; JSON returns `503 Service Unavailable`. |

## Consequences

- The UI polls the question resource while work is pending instead of holding a web request open for a provider call.
- Q&A currently retrieves only document-backed knowledge, but the answering layer consumes a source-neutral contract.
- Phase 08 can introduce `KnowledgeSource`, `KnowledgeEntry`, and shared chunks without rewriting the question controller or answer provider.
- Notes and memos should be the first non-document source. Git and project integrations require separate sync, credential, deletion, and allowlist policies.

## Verification requirements

- Model coverage for validation, ownership, claims, duplicate delivery, and completion.
- Retriever coverage for ownership, relevance, context budgets, and source diversity.
- Provider coverage for missing configuration, grounding instructions, valid citations, and invented citations.
- Job coverage for success, insufficient context, duplicate delivery, retry, and safe terminal failure.
- Controller coverage for HTML, JSON, validation, and two-user isolation without live provider calls.
