# Knowledge Service

Knowledge Service is a Rails application for organizing user-owned workspaces and uploaded documents. It extracts document content into searchable chunks, optionally enriches images with OpenAI Vision, generates OpenAI embeddings, and provides workspace-scoped semantic search.

## Features

- Session-based authentication with password-reset support.
- User-owned workspaces and many-to-many document assignment.
- Upload validation (required file, supported type, maximum size of 50 MB) and Active Storage-backed files.
- Background extraction and chunking for documents, with OCR for images and sparse PDF pages when local tools are available.
- Optional OpenAI embeddings stored in PostgreSQL/pgvector and cosine-similarity search limited to the current user's workspace.
- Optional OpenAI Vision enrichment for image content that local OCR cannot read.

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
| `DB_HOST` | No | PostgreSQL host; defaults to `localhost`. |
| `DB_USERNAME` / `DB_PASSWORD` | Depends | PostgreSQL credentials; production requires both. |
| `OPENAI_API_KEY` | No | Enables document embeddings, semantic search, and image enrichment. |
| `OPENAI_EMBEDDING_MODEL` | No | Embedding model; defaults to `text-embedding-3-small`. |
| `OPENAI_EMBEDDING_DIMENSIONS` | No | Must remain `1536` unless the `document_chunks.embedding` column is migrated to a different vector size. |
| `OPENAI_EMBEDDING_BATCH_SIZE` | No | Number of chunks per embedding request; defaults to `100`. |
| `OPENAI_VISION_MODEL` | No | Vision model for image descriptions; defaults to `gpt-4o-mini`. |

Without `OPENAI_API_KEY`, document extraction and chunking still run, but the document remains `processed` rather than `ready`, so semantic search is unavailable. Image enrichment is also skipped. Development and production use local Active Storage by default; configure an S3 service in [`config/storage.yml`](config/storage.yml) and select it in the relevant environment before using object storage.

## How processing works

1. Uploading a document queues `ProcessDocumentJob`.
2. The job extracts structured text, stores extraction metadata, and creates document chunks.
3. Documents containing image references run optional vision enrichment.
4. After enrichment finishes (or is skipped), documents with chunks run `EmbedDocumentJob`, which stores 1,536-dimension vectors using the configured embedding model.
5. Workspace search embeds the query and returns only the signed-in user's embedded chunks that belong to that workspace.

The stages run sequentially, and the document has one lifecycle status from `pending` through `ready`. Processing retries transient failures. Check the document status and application logs when a job fails.

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

The repository includes a production Dockerfile and Kamal configuration. Before deploying, replace the placeholder server and registry settings in [`config/deploy.yml`](config/deploy.yml), configure `RAILS_MASTER_KEY` and database credentials in the deployment secrets, and ensure the production PostgreSQL server provides the `vector` extension. The configured production process runs Solid Queue within Puma (`SOLID_QUEUE_IN_PUMA=true`).

The health-check endpoint is available at `/up`.
