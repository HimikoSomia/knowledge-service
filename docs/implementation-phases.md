# Implementation Phases

This document is the durable index for the application-update phases. It records what each phase is intended to accomplish and links to detailed decisions. Update it when a phase begins or finishes so future work does not depend on conversation history.

| Phase | Status | Scope |
| --- | --- | --- |
| 01 | Complete | Dependency security updates. |
| 02 | Complete | Embedding-job retry, discard, and failure policy. |
| 03 | Complete | Idempotent document processing, duplicate-delivery protection, and stale-generation rejection. |
| 04 | Complete | Explicit enrichment outcomes for success, skipped configuration, partial image failure, transient retry, and exhausted retry. See [ADR 0001](decisions/0001-enrichment-outcome-semantics.md). |

## Phase 04 acceptance summary

- Missing OpenAI configuration records a skipped enrichment outcome and continues processing.
- Transient provider or network errors escape the enrichment service/job boundary so Active Job retries them.
- A permanent failure affecting one image is recorded for that image while other images may still succeed.
- Exhausted retries preserve extracted text and leave the document processed but explicitly not fully enriched.
- `enriched_at` is written only after the enrichment stage reaches its defined completed outcome; skipped and partial outcomes are represented separately.
- README lifecycle documentation and the document status display reflect these outcomes.
- Focused tests cover success, skipped, transient retry, partial success, and exhausted retry without live provider calls.

Implementation requests do not authorize staging, committing, or pushing these changes. The repository-wide version-control rules in [`AGENTS.md`](../AGENTS.md) apply to every phase.
