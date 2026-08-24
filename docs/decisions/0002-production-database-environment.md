# ADR 0002: Production Database Environment

- Status: Accepted for Phase 05
- Date: 2026-08-24
- Owners: Application maintainers

## Context

The production database configuration requires `DB_USERNAME` and `DB_PASSWORD`, while the documented `DB_HOST` was previously applied only to development. In a deployed container this can make Active Record fall back to a local PostgreSQL socket even though the deployment documentation describes an external database host.

The application also uses separate primary, Solid Cache, Solid Queue, and Solid Cable databases. A single implicit `DATABASE_URL` can override the primary connection without clearly configuring the other three roles.

## Decision

Production uses the discrete environment variables `DB_HOST`, `DB_PORT`, `DB_USERNAME`, and `DB_PASSWORD`:

- `DB_HOST`, `DB_USERNAME`, and `DB_PASSWORD` are required in production and fail fast during configuration rendering when absent.
- `DB_PORT` is optional and defaults to PostgreSQL port `5432`.
- The primary production anchor supplies the same server and credentials to the primary, cache, queue, and cable database configurations.
- Kamal injects the host and credentials through its secrets contract and passes the port as a clear non-secret setting.
- `DATABASE_URL` is not part of the supported production deployment contract and must not be set alongside the discrete variables.

## Validation

Configuration verification must render and inspect the production database settings with placeholder environment values. It must not establish a connection, create a database, run a migration, or otherwise access a real production server.

## Consequences

- Operators must provision all four named production databases on the configured PostgreSQL server.
- A non-default port requires `DB_PORT` in the deployment environment.
- A future move to URL-based configuration requires a coordinated decision covering every database role and corresponding documentation.
