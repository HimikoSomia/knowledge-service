# AGENTS.md

This is the repository-wide operating guide for AI agents working on `knowledge-service`. It applies to Rails code, views, jobs, services, migrations, assets, tests, credentials, deployment configuration, documentation, generated files, and project structure.

A nested `AGENTS.md` adds instructions for its subtree. More specific local instructions win for local concerns, but they may not silently weaken the root requirements for authentication, ownership, data integrity, secret handling, verification, database safety, or protection of user work.

## Must Read For Every Change

Use this checklist for routine work. Read only the task-specific files relevant to the requested change.

- Inspect the relevant code, tests, documentation, and current repository patterns; check `git status --short` before significant edits.
- Preserve public behavior, authentication, ownership boundaries, data integrity, secrets, and unrelated user work unless the request explicitly changes them.
- Prefer the smallest Rails-conventional implementation that is correct. Do not introduce speculative abstractions, dependencies, client-side state, concurrency, or optimization.
- Keep request handling in controllers, persistence rules in models, multi-step workflows and external integrations in services, presentation in views/helpers, and schema changes in migrations.
- Scope every browser operation on user-owned data through `Current.user`; resolve submitted record IDs through user-scoped associations.
- Add focused tests for behavior changes and update related routes, views, jobs, models, migrations, fixtures, configuration examples, or documentation when required.
- Run the most relevant verification available and report exactly what changed, what ran, and what remains unverified.
- Never read, print, summarize, or copy real secret values unless the user explicitly requests that exact inspection.

Ask a focused question when an assumption would materially affect public behavior, authentication, ownership, data integrity, destructive behavior, or architecture. Otherwise use the smallest repository-backed assumption and state it when relevant.

## Application And Repository Map

`knowledge-service` is a Ruby on Rails 8.1 application for organizing user-owned workspaces, uploaded documents, notes, and memos. It turns content into searchable chunks, optionally enriches document images with OpenAI Vision, creates OpenAI embeddings, and provides workspace-scoped semantic search and grounded answers.

```text
Browser -> Router -> Controller -> Model / Service -> PostgreSQL / Active Storage / provider
                                      |
                                      -> Active Job -> extraction -> enrichment -> embedding
```

The application uses session authentication through `Current.session` / `Current.user`, PostgreSQL with pgvector through `neighbor`, Active Storage, Solid Queue/Cache/Cable, Hotwire, Stimulus, Tailwind CSS, DaisyUI, Propshaft, importmap-rails, Docker, Kamal, Puma, and Thruster.

```text
app/controllers/             Authentication gates, scoped loading, request handling, redirects.
app/controllers/concerns/    Shared controller behavior, especially authentication.
app/models/                  Active Record associations, validations, scopes, persistence behavior.
app/services/                Extraction, chunking, enrichment, embedding, retrieval, workflows.
app/jobs/                    Active Job orchestration and document-processing stages.
app/views/                   ERB pages, layouts, partials, forms, and mailer views.
app/helpers/                 Presentation helpers only.
app/javascript/              Stimulus controllers and importmap entrypoint.
app/assets/tailwind/         Tailwind source and DaisyUI plugin files.
app/assets/builds/           Generated assets; rebuild rather than hand-edit.
config/                      Routes, environments, database, storage, deploy, importmap, initializers.
db/migrate/                  Additive Active Record migrations.
db/schema.rb                 Generated application schema snapshot.
db/*_schema.rb               Rails-managed Solid Cable/Cache/Queue schemas.
test/                        Minitest tests, fixtures, helpers, and fixture files.
```

Keep new code inside these boundaries unless a larger structural change is explicitly requested.

## Task-Specific Guidance

The root checklist always applies. Combine rows when a change spans areas.

| Task area | Inspect first |
| --- | --- |
| Routes, REST shape, status codes, or redirects | `config/routes.rb`, affected controller, views, and controller tests |
| Authentication, sessions, password reset, or public access | `app/controllers/concerns/authentication.rb`, session/password controllers, `app/models/current.rb`, `app/models/session.rb`, related tests |
| Workspaces, ownership, or workspace search | Workspace controller/model/service, retrieval service, related views and tests |
| Notes, memos, or manual knowledge indexing | `KnowledgeSource`, `KnowledgeChunk`, knowledge-source controller/views, `IndexKnowledgeSourceJob`, text splitter, combined workspace search, related tests |
| Documents, uploads, or workspace assignment | Document controller/model, `DocumentWorkspace`, Active Storage attachment behavior, related views and tests |
| Extraction, OCR, chunking, or supported file types | `app/services/extraction/`, `app/services/chunking/`, `ProcessDocumentJob`, document model, fixtures, README, related tests |
| Enrichment, embeddings, vector search, or processing lifecycle | Enrichment/embedding/retrieval services, all document-processing jobs, document/chunk models, vector migrations/schema, `.env.example`, README, related tests |
| Background jobs, retries, or recurring work | `app/jobs/`, `config/queue.yml`, `config/recurring.yml`, affected models/services, job tests |
| Database schema, associations, indexes, or constraints | `db/schema.rb`, all relevant migration history, affected models, fixtures, queries, and tests |
| Storage or S3 | `app/models/document.rb`, `config/storage.yml`, affected environment configuration, Active Storage migrations, upload tests, README |
| Layout, navigation, page titles, or styling | `app/views/layouts/`, affected views/helpers, `app/assets/tailwind/application.css` |
| Stimulus or browser behavior | `app/javascript/controllers/`, connected ERB data attributes, Turbo behavior |
| Runtime configuration or deployment | Consuming code, `.env.example`, README, relevant environment files, `Dockerfile`, `config/deploy.yml`, `.kamal/` |

## Global Engineering Rules

These rules are mandatory unless an explicit user requirement authorizes a compatible change.

### Decision Order

When several implementations are valid, prefer them in this order:

1. Correctness.
2. Authentication, ownership, security, and data integrity.
3. Rails conventions, readability, and maintainability.
4. Simplicity and operational clarity.
5. Measured performance appropriate to expected scale.
6. Architectural novelty.

Performance may move higher only for a demonstrated bottleneck, clearly unsuitable query/algorithm, or documented resource constraint. Keep necessary complexity local and explain it.

### Rails Boundaries

- Controllers stay thin: authenticate, load scoped records, validate permitted input, invoke models/services, and render or redirect.
- Models own associations, validations, composable scopes, and persistence-related behavior. Keep callbacks small and predictable.
- Services are plain Ruby objects for external integrations or multi-step workflows. Do not create services for simple CRUD that Active Record already expresses clearly.
- Jobs orchestrate retryable asynchronous work through `ApplicationJob`; keep business logic in models/services where it can be tested directly.
- Views render prepared state. Helpers format or present data and must not mutate records or call external services.
- Use Stimulus for small explicit browser behaviors and prefer Turbo/server-rendered HTML over custom client-side state.
- Use narrow abstractions only when they create a real boundary or test seam. Add new directories only when Rails' existing structure cannot express the problem cleanly.
- Prefer plain Ruby objects (POROs) when domain logic does not require Active Record persistence, HTTP state, or framework lifecycle behavior.
- A PORO does not require a dedicated `app/poros/` directory. Place it in the smallest existing domain or module location that makes its responsibility obvious.
- Extract a PORO when it gives a business concept a clear name, isolates calculation or decision logic, or creates a useful test seam. Do not extract one only to reduce another class's line count.

### Pragmatic Design And Boring Code

Use SOLID principles as design guidance, not as a requirement to introduce patterns or layers.

- Give classes and methods one cohesive responsibility, but do not split them to satisfy an arbitrary size limit.
- Prefer Rails built-ins and ordinary Ruby before adding abstractions, gems, framework layers, or custom infrastructure.
- Prefer explicit code and small duck-typed interfaces over clever metaprogramming, deep inheritance, formal interface layers, reflection-driven dispatch, callback chains, or DSLs.
- Prefer composition when behavior genuinely varies. Add extension points only when a real second implementation or demonstrated source of change exists.
- Inject external dependencies when it creates a useful test seam. Do not add dependency-injection frameworks or wrapper layers without a concrete need.
- Do not create interfaces, factories, strategies, repositories, base classes, adapters, or other specialized objects speculatively. Use a named pattern only when the current problem requires it.
- Small duplication is preferable to the wrong abstraction. Refactor after a stable pattern becomes clear rather than predicting future reuse.
- Keep necessary complexity close to the problem that requires it, and optimize only for measured bottlenecks or clearly unsuitable queries and algorithms.
- Do not change working code merely to fit a preferred pattern. Preserve reasonable repository conventions when multiple styles would be valid.

### Authentication And Ownership

- `ApplicationController` includes `Authentication`, so actions require authentication by default.
- Use `allow_unauthenticated_access` only for intentionally public actions such as login and password reset.
- Derive ownership from `Current.user`; never trust a client-provided `user_id`.
- Load user-owned records through associations such as `Current.user.workspaces.find(params[:id])`, not global model lookups.
- Resolve submitted association IDs through the current user's scoped associations to prevent IDOR.
- Cross-user resources must normally produce the same not-found response as missing resources.
- Every owned-resource behavior change requires a two-user isolation test at the controller, service, or query boundary.
- Background jobs may load records globally by ID because they run outside a browser session, but user ownership must remain intact in every related query and association change.
- Keep authentication messages generic. Do not reveal whether an email exists during login or password reset.
- Never log raw passwords, reset tokens, session IDs, cookies, authorization headers, or unfiltered secret-bearing parameters.

### Models, Queries, And Data Integrity

- Use clear Active Record associations and appropriate `dependent:` behavior.
- Put application validations near the model rule and add database constraints when correctness must hold under concurrency.
- Add indexes for foreign keys, uniqueness, and demonstrated frequent lookups.
- Avoid N+1 queries with `includes`, `preload`, or appropriate scoped queries.
- Multi-record business outcomes should be transactional when partial persistence would be invalid.
- Keep lifecycle transitions explicit. Do not bypass validations or callbacks with `update_columns`, bulk writes, or direct SQL without inspecting and preserving the intended invariants.
- When changing associations, verify models, foreign keys, delete behavior, migrations, schema, fixtures, and tests agree.

### Database And Migrations

- Inspect `db/schema.rb`, all relevant migration history, existing rows/fixtures, affected models, and dependent queries before editing.
- Add a new migration; do not change an already-applied migration unless the user explicitly authorizes migration-history cleanup.
- Preserve existing data unless destructive behavior is explicitly requested.
- Keep migrations reversible when practical. Use `reversible`, `up`/`down`, or an explicit irreversible declaration with a clear reason.
- Review backfill ordering, defaults, nullability, uniqueness, foreign-key deletion, indexes, locking risk, transaction behavior, and deployment ordering.
- Do not manually edit generated schema files. Run the appropriate Rails task and inspect the generated diff.
- Keep Rails-managed Solid Queue, Cache, and Cable schemas separate from application migrations.
- This application uses pgvector with 1,536-dimension document embeddings. Changes to vector dimensions must coordinate the migration, provider request, validation, configuration examples, tests, and README.
- Run migrations only against an explicitly selected local development or isolated test database. Never run migration checks against production, staging, or an unspecified external database.

### Document Processing, Jobs, And Providers

- Preserve the documented processing lifecycle and coordinate status changes across `Document`, processing jobs, services, views, and tests.
- Jobs must be safe under retries and duplicate delivery. Test idempotency, failure state, retry/discard behavior, and lifecycle transitions when those behaviors change.
- Extraction/chunk replacement and other multi-write stages must not leave misleading partial state.
- Use Active Storage APIs for files; do not manually construct storage paths.
- Treat native OCR/Poppler tools as optional runtime dependencies unless deployment requirements explicitly change.
- Stub or fake OpenAI, storage, mail, and other providers in tests. Tests must never require real credentials, make real provider calls, or mutate external resources.
- Keep provider errors safe for users and logs; do not expose request payloads, document contents, credentials, or raw sensitive responses.
- Preserve workspace and user scoping in semantic-search queries and add isolation coverage when retrieval behavior changes.

### Controllers, Views, And Frontend

- Prefer RESTful `resources` / `resource` routes. Before adding a custom action, consider a nested resource or separate controller.
- Use strong parameters with `params.expect` or `require(...).permit(...)`, following the surrounding controller style.
- Render validation failures with `:unprocessable_entity` and use `:see_other` for destructive redirects when appropriate for Turbo.
- Prefer Rails form/path helpers over hardcoded URLs and use existing Turbo-compatible method attributes.
- Use `content_for` for page-specific layout content and extract repeated presentation into partials.
- Keep UI changes consistent with existing Tailwind/DaisyUI patterns.
- Do not hand-edit generated Tailwind output. Change templates or Tailwind source, then rebuild it.
- Avoid adding npm or other frontend tooling unless there is a concrete need and the project does not already provide the capability.

### Configuration, Secrets, And User Work

- Do not run `git add`, create or amend commits or tags, push branches, or create/update pull requests unless the user explicitly requests that exact version-control action. A request to implement, fix, or finish a phase does not authorize committing or pushing; leave changes unstaged and report them.
- Do not read, print, summarize, or copy values from real `.env` files or decrypted credentials unless explicitly asked to inspect those exact values.
- `.env` and `config/master.key` must not be committed. `config/credentials.yml.enc` may be committed.
- Use `.env.example` for variable names and non-secret placeholders only.
- Prefer `ENV.fetch` for required runtime configuration and safe documented defaults where optional behavior is intentional.
- Never hardcode passwords, tokens, database URLs, AWS/OpenAI keys, session values, cookies, personal data, or production identifiers.
- Configuration changes must update consuming code, `.env.example`, README configuration, tests, and deployment/environment configuration where applicable.
- Keep documentation truthful and identify placeholders or unverified behavior explicitly.
- Protect unrelated user changes. Do not combine requested work with cleanup, formatting, dependency churn, generated noise, or package reshuffling.
- New gems or external services require a concrete need and must not duplicate an existing capability.
- Ask before destructive file/database operations, migration rollback, history rewrite, or intentional modification of real external resources.

## Testing And Verification

Every behavior change needs focused tests at the lowest useful layer.

### Test Database Permission

Agents are authorized to use the repository's isolated local test database for verification without asking for additional approval. When the environment is explicitly `RAILS_ENV=test`, agents may run as needed:

```bash
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bin/rails db:migrate
RAILS_ENV=test bin/rails test
RAILS_ENV=test bin/rails runner ...
```

Before database lifecycle commands, verify that the environment is `test` and the configuration clearly resolves to this repository's isolated local test database. Do not proceed if it resolves to production, staging, a shared database, or an unknown external `DATABASE_URL`. Do not print a secret-bearing database URL while checking.

Ordinary test-data creation, mutation, transaction rollback, fixture loading, and cleanup performed by the test suite do not require approval. Runtime sandbox or host security confirmations still apply and cannot be overridden by this file.

Explicit approval remains required for production or staging operations, unknown or shared external databases, development database destruction, destructive commands outside an established isolated test database, operations that could affect user-created data, and parallel tests that create additional databases.

- Keep the Rails test suite single-process by default. Do not enable process-based parallel tests that create numbered `knowledge_service_test_*` databases unless the user explicitly requests parallel execution and approves the database lifecycle. Remove approved temporary worker databases when that run is complete.
- Model changes: validations, associations, lifecycle methods, and edge cases.
- Controller changes: success, validation failure, authentication, authorization, response status, and redirect/render behavior.
- Ownership changes: two-user isolation and submitted foreign-ID coverage.
- Transactional changes: rollback or partial-failure coverage where practical.
- Job changes: enqueue behavior, retries/discards, idempotency, lifecycle transitions, and failure state.
- Provider changes: fakes/stubs and safe error mapping; no credentials or live calls.
- Retrieval changes: user/workspace isolation, embedding-model compatibility, and missing-configuration behavior.
- Migration/query changes: PostgreSQL verification against an explicitly selected isolated database when available.
- View/asset changes: relevant rendering tests plus a Tailwind rebuild when class discovery/output changes.

Run focused tests while iterating, then the full suite when available:

```bash
RAILS_ENV=test bin/rails db:prepare
bin/rails test test/models/document_test.rb
bin/rails test test/controllers/workspaces_controller_test.rb
bin/rails test
```

For broader or riskier changes, run the applicable checks:

```bash
bin/rubocop
bin/brakeman
bin/bundler-audit
bin/rails tailwindcss:build
bin/ci
```

Documentation-only changes require diff, path, link, and Markdown inspection rather than Rails tests unless the documentation makes claims that require runtime verification.

If PostgreSQL, gems, native tools, browser support, network access, or credentials prevent a check, run all other relevant checks and report the exact gap. Never claim tests, migrations, asset builds, or runtime behavior were verified unless they actually were.

## Common Commands

Run from the repository root. Commands that prepare or migrate databases must target an intentionally selected environment.

```bash
# Install dependencies, prepare the local development databases, and start development services.
bin/setup

# Start Rails and the Tailwind watcher.
bin/dev

# Start the Solid Queue worker when it is not running inside Puma.
bin/jobs

# Prepare or migrate the isolated test database.
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bin/rails db:migrate

# Run the full test suite and project CI.
bin/rails test
bin/ci
```

## Working Method And Reviews

For implementation, inspect first, read the matching task-specific context, identify acceptance criteria for non-trivial work, make the smallest correct change, update related surfaces, verify, and summarize changed files and remaining risk.

For review, lead with findings ordered by severity and include file/line references where possible. Prioritize:

- Authentication, authorization, ownership, session, or secret-handling risks.
- Cross-user data leaks or unscoped Active Record queries.
- Migration, constraint, data-loss, lifecycle, transaction, or schema consistency risks.
- Job retry/idempotency problems and unsafe provider behavior.
- Controller regressions, unsafe errors, incorrect statuses, or Turbo-unfriendly redirects.
- Missing validations/indexes, N+1 queries, and request/query performance issues.
- Broken route/view helpers, configuration drift, or generated asset assumptions.
- Missing or weak tests.

If no findings exist, say so and identify meaningful test or runtime coverage gaps. Final responses must state what changed, what was verified, and any remaining manual step without overstating completeness.
