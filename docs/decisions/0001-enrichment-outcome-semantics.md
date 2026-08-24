# ADR 0001: Enrichment Outcome Semantics

- Status: Accepted for Phase 04
- Date: 2026-08-24
- Owners: Application maintainers

## Context

Document extraction can produce image references that are optionally described through OpenAI Vision. Enrichment is not an all-or-nothing prerequisite for retaining extracted text, but its current lifecycle must distinguish configuration absence, retryable provider failure, permanent per-image failure, partial success, and full success.

Without explicit outcomes, a skipped or partially failed stage can appear successfully enriched, provider failures can be swallowed instead of retried, and the UI cannot accurately explain why a document contains only some enriched image content.

## Decision

Phase 04 will implement the following policy:

1. Missing OpenAI configuration is an expected optional-capability outcome. Record enrichment as skipped and continue the document pipeline without calling the provider.
2. Transient API, rate-limit, timeout, and network failures remain exceptions at the job boundary. Active Job owns their retry schedule.
3. A permanent failure limited to one image is recorded against that image. Processing continues for the remaining image references, allowing a partial-success document outcome.
4. When the enrichment job exhausts its retries, preserve extraction output and text chunks. Transition the document to processed-but-not-fully-enriched instead of discarding extracted data or presenting enrichment as successful.
5. `enriched_at` is set only after the stage has genuinely reached its defined completed outcome. The persisted outcome, rather than the timestamp alone, communicates whether completion was successful, skipped, partial, or unsuccessful.
6. The document status display and README lifecycle description expose the persisted outcome in user-understandable language.

## Outcome model requirements

The implementation must be able to represent these distinct states without overloading the document's main processing status:

| Outcome | Meaning | Pipeline behavior |
| --- | --- | --- |
| Not started / pending | Image references require an enrichment decision. | Wait for the enrichment job. |
| In progress | A claimed job execution is processing image references. | Prevent duplicate work through the Phase 03 job claim. |
| Succeeded | Every eligible image was enriched successfully. | Continue to the next processing stage. |
| Skipped | Enrichment is unavailable because optional configuration is missing. | Continue without Vision output. |
| Partial | At least one image succeeded and at least one permanent image failure was recorded. | Retain successful descriptions and continue. |
| Failed after retries | A stage-wide transient failure exhausted its retry policy. | Retain extracted text and mark processing complete but not fully enriched. |

Exact column names and whether per-image outcomes use chunk metadata or a dedicated persisted structure are implementation details. Choose the smallest design that provides durable status, safe retries, deterministic per-image identity, and clear queries. Any schema change must be additive and database-backed where integrity matters.

## Error classification boundary

- Configuration absence is not an exception and must not retry.
- Retryable service and transport errors must not be converted into per-image permanent failures.
- Permanent image-specific errors may be captured and persisted without failing the whole job.
- Unknown errors remain retryable unless the provider boundary can classify them safely as permanent.
- User-visible messages and logs must not include credentials, raw provider payloads, document contents, or sensitive responses.

## Timestamp semantics

`enriched_at` must be written only after the final outcome is persisted. It must never be set when enrichment is merely queued, claimed, or interrupted by an exception. The explicit enrichment outcome remains the authoritative indicator of success, skip, partial completion, or exhausted failure.

## Verification matrix

| Scenario | Expected verification |
| --- | --- |
| All images succeed | Deterministic description chunks are stored once, outcome is succeeded, completion time is recorded, and the next stage is queued once. |
| OpenAI configuration missing | Provider is not called, outcome is skipped, and processing continues once. |
| Transient provider/network error | The job records no false success, raises, and follows the configured Active Job retry policy. |
| One permanent image failure | Failure details are safely persisted for that image, successful descriptions remain, and document outcome is partial. |
| Retry succeeds after an earlier transient failure | Existing deterministic image output is not duplicated and final outcome reflects the completed run. |
| Retries exhausted | Extracted content and core chunks remain, outcome records exhausted failure, and the document is processed but not fully enriched. |
| Duplicate or stale delivery | Phase 03 generation/job claims prevent provider calls and writes from superseded executions. |

Tests must use fakes or stubs and must not require credentials or live provider calls.

## Documentation and UI consequences

- Update the README processing lifecycle with skipped, partial, and exhausted enrichment outcomes.
- Update document status presentation so users can distinguish main processing status from enrichment outcome.
- Avoid exposing raw provider errors. Display concise language with a retry or configuration implication only when useful.

## Implementation result

Phase 04 uses an additive `documents.enrichment_status` column constrained to `not_required`, `pending`, `in_progress`, `succeeded`, `skipped`, `partial`, or `failed`. The main document processing status remains independent.

Each eligible image reference stores a safe terminal result inside its existing `extracted_content` section under `enrichment.status` and, for non-success outcomes, `enrichment.error_code`. Raw provider messages and payloads are not persisted. Successful description chunks retain the deterministic `image_ref:<section index>` source key introduced in Phase 03.

The enrichment job persists outcomes before handoff, retries transient and unknown stage errors through Active Job, finalizes invalid provider configuration without retrying, and restores its processing claim if the next job cannot be enqueued. Exhausted stage failures leave extraction data and core chunks intact with the document in `processed` and enrichment in `failed`.

## Out of scope

- Changing embedding dimensions or embedding-provider selection.
- Adding a second Vision provider.
- Reprocessing historical documents automatically without an explicit migration/backfill decision.
- Introducing client-side lifecycle state when server-rendered status is sufficient.
