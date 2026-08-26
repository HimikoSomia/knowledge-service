# Implementation Phases

This document is the durable index for the application-update phases. It records what each phase is intended to accomplish and links to detailed decisions. Update it when a phase begins or finishes so future work does not depend on conversation history.

| Phase | Status | Scope |
| --- | --- | --- |
| 01 | Complete | Dependency security updates. |
| 02 | Complete | Embedding-job retry, discard, and failure policy. |
| 03 | Complete | Idempotent document processing, duplicate-delivery protection, and stale-generation rejection. |
| 04 | Complete | Explicit enrichment outcomes for success, skipped configuration, partial image failure, transient retry, and exhausted retry. See [ADR 0001](decisions/0001-enrichment-outcome-semantics.md). |
| 05 | Complete | Standardize production PostgreSQL configuration on discrete host, port, username, and password variables. See [ADR 0002](decisions/0002-production-database-environment.md). |
| 06 | Complete | Enforce workspace validation and same-owner document/workspace joins, with controller and isolation coverage. See [ADR 0003](decisions/0003-workspace-ownership-integrity.md). |
| 07 | Complete | Add asynchronous grounded workspace Q&A with citation snapshots, neutral retrieval results, authenticated HTML/JSON resources, and duplicate-delivery protection. See [ADR 0004](decisions/0004-grounded-workspace-qa.md). |
| 08 | Complete | Add user-authored notes and memos with safe background indexing and multi-source workspace retrieval. See [ADR 0005](decisions/0005-manual-workspace-knowledge.md). |

## Long-term productization target

The intended final product is an embeddable, configurable Rails Engine gem with this repository retained as its standalone reference application. Gem extraction is directional and is not yet assigned to an implementation phase; retrieval evaluation and at least one real external source should establish the required extension boundaries first. See [Long-Term Productization Target](productization-target.md).

## Phase 04 acceptance summary

- Missing OpenAI configuration records a skipped enrichment outcome and continues processing.
- Transient provider or network errors escape the enrichment service/job boundary so Active Job retries them.
- A permanent failure affecting one image is recorded for that image while other images may still succeed.
- Exhausted retries preserve extracted text and leave the document processed but explicitly not fully enriched.
- `enriched_at` is written only after the enrichment stage reaches its defined completed outcome; skipped and partial outcomes are represented separately.
- README lifecycle documentation and the document status display reflect these outcomes.
- Focused tests cover success, skipped, transient retry, partial success, and exhausted retry without live provider calls.

Implementation requests do not authorize staging, committing, or pushing these changes. The repository-wide version-control rules in [`AGENTS.md`](../AGENTS.md) apply to every phase.
