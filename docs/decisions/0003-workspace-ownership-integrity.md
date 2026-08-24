# ADR 0003: Workspace Ownership Integrity

- Status: Accepted for Phase 06
- Date: 2026-08-24
- Owners: Application maintainers

## Context

Workspaces and documents are both owned by a user, but the `document_workspaces` join previously validated neither uniqueness nor matching owners. The database already prevents duplicate pairs and missing foreign records, while the application needed a clear same-owner invariant and useful validation errors before persistence.

An unused `WorkspaceService` also exposed methods that accepted arbitrary workspace and document model objects. Although current controllers did not call it, that API provided an unnecessary path around user-scoped loading.

## Decision

- A workspace requires a non-blank name at the model boundary. The existing non-null database column remains the structural safeguard.
- Workspace create and update validation failures render with HTTP 422 (`unprocessable_entity`).
- A `DocumentWorkspace` is valid only when its document and workspace belong to the same user.
- The join model validates pair uniqueness for clear application errors; the existing unique database index remains authoritative under concurrency.
- Deleting a workspace or document deletes its join records through the existing dependent associations without deleting the record on the other side.
- Remove the unused `WorkspaceService` rather than retain methods that accept arbitrary model objects. Controllers continue to load owned records through `Current.user` associations.

## Verification

Tests cover workspace name validation, create/update failure status, join uniqueness, cross-user rejection in both owner directions, and deletion behavior for both sides of the join. No live provider or external resource is involved.
