# Knowledge Service

Knowledge Service is a Rails application for organizing user-owned workspaces and uploaded documents. It extracts document content into searchable chunks, optionally enriches images with OpenAI Vision, generates OpenAI embeddings, and provides workspace-scoped semantic search.

## Features

- Session-based authentication with password-reset support.
- User-owned workspaces and many-to-many document assignment.
- Upload validation (required file, supported type, maximum size of 50 MB) and Active Storage-backed files.
- Background extraction and chunking for documents, with OCR for images and sparse PDF pages when local tools are available.
- Optional OpenAI embeddings stored in PostgreSQL/pgvector and cosine-similarity search limited to the current user's workspace.
- Optional OpenAI Vision enrichment for image content that local OCR cannot read.
- Asynchronous workspace Q&A grounded in retrieved knowledge, with persisted source citations and authenticated HTML/JSON responses.

## Supported documents

The extraction pipeline accepts PDF; DOCX; XLSX, XLS, and ODS spreadsheets; PPTX; plain text and Markdown; CSV; JSON; HTML/XML; and JPEG, PNG, WebP, GIF, TIFF, BMP, HEIC, and HEIF images. Browser file-picker hints are narrower than server-side validation, so the server is the authoritative list.

## Requirements

- Ruby 3.4.9 (see [`.ruby-version`](.ruby-version))
- PostgreSQL with the `vector` extension available
- Bundler

Optional native utilities improve extraction:

- [Tesseract](https://tesseract-ocr.github.io/) for OCR of image uploads and scanned/sparse PDF pages
- Poppler utilities (`pdfimages` and `pdftoppm`) for extracting or rendering PDF page images

The production Docker image installs Tesseract and Poppler. On macOS, for example, install them with Homebrew: `brew install tesseract poppler`.

## Getting started

1. Install Ruby dependencies and configure local environment variables:

   ```sh
   bundle install
   cp .env.example .env
   ```

   Edit `.env` with the PostgreSQL credentials for your local role. The default development database names are `knowledge_service_development` plus separate Solid Cache, Solid Queue, and Solid Cable databases.

2. Ensure PostgreSQL is running and has the `vector` extension installed. The database user must be allowed to create or use that extension; the application migration enables it.

3. Prepare the databases:

   ```sh
   bin/rails db:prepare
   ```

   Alternatively, `bin/setup` installs dependencies, prepares databases, clears temporary files, and starts the development server.

4. Start the web and CSS development processes:

   ```sh
   bin/dev
   ```

5. In another terminal, start the Solid Queue worker so uploads are processed:

   ```sh
   bin/jobs
   ```

   Visit `http://localhost:3000`. The app has sign-in but no public registration flow or seeded users; create a development user from the Rails console:

   ```sh
   bin/rails console
   User.create!(email_address: "developer@example.test", password: "change-me", password_confirmation: "change-me")
   ```

## Configuration

Copy [`.env.example`](.env.example) to `.env`; dotenv loads it in development and test. Do not commit `.env` or real credentials.

| Variable | Required | Purpose |
| --- | --- | --- |
| `DB_HOST` | Development: no; production: yes | PostgreSQL host. Development defaults to `localhost`; production fails fast when it is absent. |
| `DB_PORT` | No | PostgreSQL port; defaults to `5432`. |
| `DB_USERNAME` / `DB_PASSWORD` | Depends | PostgreSQL credentials; production requires both. |
| `OPENAI_API_KEY` | No | Enables document embeddings, semantic search, and image enrichment. |
| `OPENAI_EMBEDDING_MODEL` | No | Embedding model; defaults to `text-embedding-3-small`. |
| `OPENAI_EMBEDDING_DIMENSIONS` | No | Must remain `1536` unless the `document_chunks.embedding` column is migrated to a different vector size. |
| `OPENAI_EMBEDDING_BATCH_SIZE` | No | Number of chunks per embedding request; defaults to `100`. |
| `OPENAI_VISION_MODEL` | No | Vision model for image descriptions; defaults to `gpt-4o-mini`. |
| `OPENAI_ANSWER_MODEL` | No | Model used for grounded workspace answers; defaults to `gpt-4o-mini`. |
| `OPENAI_ANSWER_MAX_TOKENS` | No | Maximum generated tokens per workspace answer; defaults to `1200`. |
| `WORKSPACE_QA_CANDIDATE_LIMIT` | No | Candidate chunks considered before relevance and diversity filtering; defaults to `24`. |
| `WORKSPACE_QA_MAX_DISTANCE` | No | Maximum cosine distance accepted as answer context; defaults to `0.55` and lower is more similar. |
| `WORKSPACE_QA_MAX_CONTEXT_CHARS` | No | Maximum total characters supplied as answer context; defaults to `16000`. |
| `WORKSPACE_QA_MAX_RESULTS_PER_SOURCE` | No | Maximum chunks contributed by one source; defaults to `3`. |

Without `OPENAI_API_KEY`, document extraction and chunking still run, but the document remains `processed` rather than `ready`, so semantic search is unavailable. Image enrichment is also skipped. Development and production use local Active Storage by default; configure an S3 service in [`config/storage.yml`](config/storage.yml) and select it in the relevant environment before using object storage.

## How processing works

1. Uploading a document queues `ProcessDocumentJob`.
2. The job extracts structured text, stores extraction metadata, and creates document chunks.
3. Documents containing eligible image references run optional vision enrichment. The enrichment outcome is tracked separately from the main processing status:
   - `succeeded`: every eligible image was described.
   - `skipped`: OpenAI Vision is not configured; extracted text is preserved and processing continues.
   - `partial`: some images were described while permanent failures were safely recorded for others.
   - `failed`: transient or stage-wide failures exhausted their retries; extracted text is preserved and the document remains processed but not fully enriched.
4. Transient Vision API and network errors are retried by Active Job. A permanent failure for one image does not discard descriptions successfully generated for other images.
5. After enrichment succeeds, is skipped, or partially succeeds, documents with chunks run `EmbedDocumentJob`, which stores 1,536-dimension vectors using the configured embedding model.
6. Workspace search embeds the query and returns only the signed-in user's embedded chunks that belong to that workspace.

The stages run sequentially, and the document has one main lifecycle status from `pending` through `ready`. Image-enrichment status is displayed separately so skipped or partial enrichment is not presented as full success. `enriched_at` is recorded only when that stage reaches a terminal outcome; it is not set while the work is merely queued, running, or waiting to retry.

## Grounded workspace Q&A

The workspace page provides two related operations:

- **Generate answer** creates a persisted question, retrieves relevant workspace chunks, and asynchronously generates an answer that must cite its sources.
- **Search matching passages** exposes the existing semantic-search results directly without generating an answer.

Question states progress from `pending` to `answering`, then to `answered`, `insufficient_context`, or `failed`. Retrieval is limited by user and workspace ownership in SQL, vector relevance, total context size, and per-source diversity. Retrieved content is treated as untrusted evidence: instructions found inside a document are not instructions for the answer provider.

Phase 07 knowledge is still backed by ready document chunks. The answering boundary uses source-neutral retrieval results so future notes, memos, Git files, and project imports can join the workspace index without changing the answer generator. Generated answers are not automatically indexed as knowledge.

Authenticated HTML and JSON resources use the same session boundary:

```text
POST /workspaces/:workspace_id/questions
GET  /workspaces/:workspace_id/questions/:id
GET  /workspaces/:workspace_id/questions
```

JSON creation returns `202 Accepted` when the answer job is queued. Clients can poll the returned question URL until it reaches a terminal status. This is a same-origin session API; external bearer tokens and CORS are not currently supported.

## Tests and checks

Run the Rails test suite:

```sh
bin/rails test
```

Useful focused checks:

```sh
bin/rails test test/services/extraction/extractors_test.rb
bin/rails test test/services/retrieval/document_search_service_test.rb
bin/rubocop
bin/brakeman
bin/bundler-audit
```

Run the full project CI sequence with:

```sh
bin/ci
```

## Deployment

The repository includes a production Dockerfile and Kamal configuration. Before deploying:

1. Replace the placeholder server and registry settings in [`config/deploy.yml`](config/deploy.yml).
2. Supply `RAILS_MASTER_KEY`, `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, and `OPENAI_API_KEY` through `.kamal/secrets`. These values are injected as container secrets and must not be committed. The default Kamal template enables the OpenAI-backed features and therefore expects the key; remove its `config/deploy.yml` secret entry only when those features are intentionally disabled.
3. Set `DB_PORT` in the deployment environment when PostgreSQL does not use port `5432`; Kamal passes it as a clear, non-secret variable.
4. Ensure the PostgreSQL server hosts `knowledge_service_production`, `knowledge_service_production_cache`, `knowledge_service_production_queue`, and `knowledge_service_production_cable`, and provides the `vector` extension.

Production is standardized on these discrete database variables. Do not also provide `DATABASE_URL`, because Rails can merge it over the primary configuration and create a different connection contract from the cache, queue, and cable databases.

The configured production process runs Solid Queue within Puma (`SOLID_QUEUE_IN_PUMA=true`).

The health-check endpoint is available at `/up`.
