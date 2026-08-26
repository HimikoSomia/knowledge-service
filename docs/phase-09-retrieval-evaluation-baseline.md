# Phase 09: Retrieval Evaluation Baseline

- Status: Planned
- Planned: 2026-08-26
- Depends on: Phase 07 grounded workspace Q&A, Phase 08 manual knowledge sources, and the browser acceptance-test foundation

## Purpose

Phase 09 will establish a repeatable baseline for workspace retrieval quality, ownership isolation, and exact-search performance before Git or project-system integrations add new source and synchronization complexity.

The phase must make these failure classes distinguishable:

- Required evidence is absent from the workspace.
- Evidence exists but embedding or ranking quality does not retrieve it.
- Retrieval is correct but filtering, diversity, or context limits remove it.
- Retrieval is correct but answer generation or citation rendering is wrong.
- Retrieval quality is acceptable but exact vector search is too slow at the measured cardinality.

The baseline informs later work; Phase 09 does not optimize retrieval merely because a benchmark exposes a weak result.

## Non-goals

Phase 09 will not:

- Add Git, GitHub, or project-system connectors.
- Add a `KnowledgeEntry` model or another production persistence abstraction.
- Add HNSW, IVFFlat, hybrid search, reranking, or a new embedding provider.
- Make live provider calls in the automated test suite or GitHub Actions.
- Put a large corpus in normal Rails fixtures or run scale benchmarks through `bin/rails test`.
- Create numbered parallel test databases or retain generated evaluation records.
- Add a production evaluation UI or API.

## Execution and database safety

Evaluation commands must:

- Require `RAILS_ENV=test` and resolve only to the repository's configured `knowledge_service_test` database.
- Reject production, staging, shared, or unrecognized external database targets before writing data.
- Use the existing single test database without process-based parallelization.
- Create an isolated evaluation user and owned workspaces inside a transaction, then roll back the run even after failure.
- Apply a unique run identifier to generated titles and metadata so accidental leftovers can be identified safely.
- Use bounded batch insertion and avoid retaining the full scale corpus in Ruby memory.
- Require the test database to be prepared separately; evaluation tasks must not create, drop, clone, or migrate databases.

Raw reports belong under ignored `tmp/evaluation/`. A reviewed summary may be committed under `docs/evaluations/` after it records the dataset revision, mode, embedding model, application revision, database version, host characteristics, and run date.

## Evaluation dataset

Add a versioned, sanitized dataset under `test/evaluation/data/`. The dataset should remain readable in source control and should describe evidence and expectations rather than storing thousands of opaque vector values.

The first dataset should include:

- At least two users and three workspaces.
- Documents, notes, and memos.
- Direct factual matches, paraphrases, multi-source questions, and terminology variants.
- Near-duplicate sources and repeated facts from different source types.
- Current and explicitly outdated or contradictory facts.
- Long sources that exercise chunk and context limits.
- Irrelevant distractors in the correct workspace.
- Cross-workspace and cross-user canary facts that must never be returned.
- Unanswerable questions for which the relevance threshold should produce no accepted context.

Each case should provide:

- A stable case identifier and descriptive tags.
- The user and workspace from which the question is asked.
- The question text.
- One or more expected source keys when the case is answerable.
- Forbidden source keys, including ownership-isolation canaries.
- Whether abstention is expected.
- Optional expected facts for a later answer-generation review.

Dataset validation must reject duplicate keys, missing references, empty questions, answerable cases without expected sources, and a forbidden source that is also expected.

## Evaluation modes

### 1. Deterministic contract mode

This mode validates the evaluator and the application's retrieval boundaries without network access.

- Generate normalized 1,536-dimension vectors deterministically from declared semantic labels.
- Exercise the real PostgreSQL/pgvector queries, document/manual candidate merge, distance filter, per-source cap, result limit, and context budget.
- Require all ownership canaries to remain absent.
- Keep the corpus small enough for local iteration.

Contract mode proves plumbing, scoping, scoring, and reporting. It must not be presented as evidence of real-language embedding quality.

### 2. Provider quality mode

This mode measures the configured embedding model against the sanitized labeled questions.

- It is manual and opt-in, requires an explicit flag and configured provider credentials, and never runs in CI.
- Embed dataset sources and queries through the existing application embedding service.
- Cache only non-secret evaluation artifacts under `tmp/evaluation/` so an interrupted run can be resumed without repeating paid requests.
- Record the model and dimensions with every report and reject incompatible cached vectors.
- Never send real user documents, credentials, or production data.

Implementing the mode does not authorize running it. A live run requires explicit user approval because it sends sanitized evaluation content to the configured provider and may incur cost.

### 3. Synthetic scale mode

This mode measures PostgreSQL behavior independently from semantic quality.

- Support explicit corpus tiers of 1,000, 10,000, and 50,000 chunks, with a guarded maximum of 100,000.
- Populate both document and manual-source chunk tables so the current two-query merge is represented.
- Generate vectors in bounded batches and reuse deterministic vector families where semantic variety is not relevant to the timing measurement.
- Warm each query before collecting repeated samples.
- Capture p50, p95, and maximum retrieval time, candidate counts, accepted-result counts, and query plans using `EXPLAIN (ANALYZE, BUFFERS)`.
- Report insertion time separately from retrieval latency.

Exact pgvector search remains the reference result set. Approximate indexes must be evaluated in a later phase against this exact-search baseline, not introduced during Phase 09.

## Metrics

Required retrieval metrics:

- **Hit rate at 8:** percentage of answerable cases with at least one expected source in the final eight contexts.
- **Recall at 8:** percentage of all expected sources present in the final contexts.
- **Mean reciprocal rank:** how early the first expected source appears.
- **Forbidden-hit count:** any cross-user, cross-workspace, or explicitly forbidden source returned at either candidate or final-context level.
- **Abstention accuracy:** percentage of unanswerable cases that produce no accepted context.
- **Context utilization:** result count, source diversity, and characters used from the configured context budget.
- **Filter-loss reasons:** counts rejected by distance, per-source cap, blank content, result limit, and context budget.
- **Latency:** p50, p95, maximum, and sample count, reported separately for candidate search and final filtering where practical.

The evaluator should emit both machine-readable JSON and a concise Markdown summary. Failed cases must identify source keys and ranks, but reports must not include credentials or unnecessary full source content.

## Provisional baseline gates

The first implementation should report these provisional targets without silently tuning production defaults to satisfy them:

- Forbidden-hit count: exactly zero.
- Contract-mode expected hit rate at 8: 100%.
- Provider-mode expected hit rate at 8: at least 90%.
- Provider-mode recall at 8: at least 85%.
- Provider-mode mean reciprocal rank: at least 0.75.
- Provider-mode abstention accuracy: at least 90%.

Scale mode records a baseline before setting a hard latency gate because local and CI hardware differ. The first reviewed 10,000- and 50,000-chunk reports should propose hardware-qualified p95 targets for subsequent regression checks.

## Planned command surface

Commands should be explicit and should not overload the normal test task:

```bash
# Network-free retrieval contract evaluation.
RAILS_ENV=test bin/rails evaluation:retrieval

# Exact-search scale benchmark at an allowed tier.
RAILS_ENV=test EVALUATION_CHUNKS=10000 bin/rails evaluation:retrieval_scale

# Manual provider-backed quality run; never a CI command.
RAILS_ENV=test LIVE_EVALUATION=1 bin/rails evaluation:retrieval_provider
```

Invalid environment, corpus tier, provider configuration, dataset, or cache metadata must fail before inserting evaluation records or calling a provider.

## Implementation sequence

1. Define and validate the versioned dataset schema.
2. Implement result and metric objects as small evaluation-only Ruby objects under `test/evaluation/support/`.
3. Add deterministic vector generation and an isolated transactional corpus loader.
4. Add contract-mode execution through the real workspace search and retriever services.
5. Add JSON and Markdown report writers under `tmp/evaluation/`.
6. Add the bounded scale-corpus loader, warmup/sampling logic, and query-plan capture.
7. Add the explicit opt-in provider mode and compatible-vector cache.
8. Unit test dataset validation, scoring, percentiles, safety guards, cleanup, and report redaction without live provider calls.
9. Keep the existing Capybara Q&A flow as the browser-level acceptance check; do not duplicate the scale corpus in browser tests.
10. Run contract and scale modes, review the first baseline, and record follow-up decisions before starting an integration phase.

## Acceptance criteria

Phase 09 implementation is complete when:

- The three modes and their boundaries are documented and implemented.
- Normal `bin/rails test` and `bin/rails test:system` remain small and do not run provider or scale evaluations.
- Contract mode produces deterministic JSON and Markdown reports and meets its isolation and hit-rate gates.
- Scale mode completes the 1,000- and 10,000-chunk tiers, records query plans and latency distributions, and cleans up all generated records.
- The 50,000-chunk tier is run when local resources permit; an inability to run it is recorded rather than hidden.
- Provider mode cannot run without both its explicit opt-in flag and valid configuration.
- No evaluation path reads production data or makes a live provider call in CI.
- Tests prove rejection of unsafe database targets and rollback after a failed evaluation.
- README and agent instructions describe the commands, safety boundary, and interpretation limits.
- A reviewed baseline summary records whether the next work should address corpus coverage, retrieval quality, answer generation, vector-search performance, or an external source.

## Decision after the baseline

Use the evidence to choose the next phase:

| Result | Recommended next work |
| --- | --- |
| Expected evidence is absent from representative workspaces | Add the highest-value external source, likely a narrow read-only Git integration. |
| Evidence exists but provider retrieval misses it | Review chunking, thresholds, hybrid lexical/vector search, or reranking before adding connectors. |
| Retrieval is strong but answers or citations are weak | Improve answer validation and grounded-answer evaluation. |
| Exact retrieval misses the hardware-qualified latency target | Compare HNSW with the exact baseline and measure recall loss. |
| Results are acceptable and code knowledge is valuable | Plan a provider-specific Git MVP with repository entries and incremental synchronization. |
| Project-state questions provide more value than code questions | Plan the selected project-system connector separately from Git. |

