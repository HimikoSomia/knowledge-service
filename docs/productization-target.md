# Long-Term Productization Target

- Status: Directional; not scheduled
- Applies after the application has established stable retrieval, source, and integration boundaries

## Target outcome

Knowledge Service should eventually be distributable as a versioned Rails Engine gem. A host Rails application should be able to add workspace knowledge ingestion, indexing, retrieval, and grounded question answering without adopting the entire standalone application.

This repository should remain a reference application that:

- Runs the gem's production code paths rather than maintaining a separate implementation.
- Demonstrates the recommended default configuration.
- Provides a development and integration-test host for the gem.

Gem extraction is a productization target, not a reason to introduce speculative abstractions into current phases. It should begin only after retrieval evaluation and at least one external source have established the extension boundaries that consumers genuinely need.

## Adoption options

A host application should be able to adopt capabilities incrementally and choose:

- Retrieval only, or retrieval with grounded answer generation.
- A bundled Rails UI, JSON endpoints, or service-layer integration only.
- Documents, authored notes and memos, Git repositories, project systems, or registered custom sources.
- Embedding and answer providers and their models.
- Active Job and Active Storage adapters supplied by the host application.
- Supported content types, retrieval limits, ranking strategy, and context budget.
- Optional enrichment and external connectors.

Unavailable or unconfigured optional features should be disabled or return a documented unavailable/skipped outcome rather than fail unpredictably.

## Host application contracts

The gem should not require a host application to replace its authentication, authorization, user model, queue, or storage configuration. It should provide narrow, documented contracts for:

- Resolving the current actor and mapping host users and workspaces to knowledge ownership.
- Authorizing access to owned resources without weakening isolation requirements.
- Mounting or disabling the bundled routes and UI.
- Installing and migrating gem-owned tables.
- Supplying provider credentials through the host application's secret-management system.
- Registering custom source, extraction, embedding, retrieval, and answer adapters.

Authentication, ownership, data isolation, safe secret handling, and provider-call boundaries remain mandatory regardless of which optional features a consumer enables.

## Design constraints

- Keep the default installation Rails-conventional and operationally understandable.
- Prefer a small set of stable extension points over making internal classes generally configurable.
- Keep external connectors optional so consumers do not inherit unused provider dependencies.
- Do not make live provider calls during installation, migration, or automated tests.
- Version configuration and migrations so host applications have a documented upgrade path.
- Test the reference application and an isolated engine host against the same public interfaces.

## Completion criteria

The target is achieved when a clean supported Rails application can:

1. Add the gem and run its installer and migrations.
2. Configure ownership resolution and one embedding provider.
3. Enable only the desired knowledge-source types and presentation surfaces.
4. Index workspace knowledge without modifying generated gem code.
5. Retrieve workspace-scoped evidence and optionally produce a grounded answer with citations.
6. Verify that another user's resources cannot be retrieved.
7. Upgrade the gem through documented, versioned migrations and configuration changes.

## Sequencing

Before extraction begins:

1. Establish a representative retrieval-quality and scale baseline.
2. Implement at least one multi-entry external source, such as a read-only Git integration.
3. Identify which boundaries are stable across the standalone application and the external source.
4. Record the engine's ownership, persistence, configuration, and public API contracts in an ADR.
5. Extract the gem while keeping the standalone application as its reference host.

