# Infrastructure

Terraform for both `ins8-tasks` (backend) and `ins8-frontend` (frontend), deployed to
Google Cloud Run, with Postgres on [Neon](https://neon.tech)'s free tier instead of
Cloud SQL (Cloud SQL has no perpetual free tier — smallest instance still bills
continuously).

One GCP project per repo — `ins8-frontend` and `ins8-tasks` each get their own
project, own Terraform state, own everything. No staging/prod split yet (see "What's
deliberately not here yet" — this is intentionally the simplest thing that works
right now, not a permanent shape). And no custom domain — the two services talk to
each other over their raw `*.run.app` URLs; see "Living without a domain" below for
what that does and doesn't cost you.

```
envs/
  ins8-frontend/   root module for the ins8-frontend project — own backend "gcs" state
  ins8-tasks/      root module for the ins8-tasks project — own backend "gcs" state
modules/
  cloud-run-service/  generic Cloud Run v2 service wrapper, used by both envs
  github-ci-identity/ Workload Identity Federation trust + a scoped deploy service
                      account for one GitHub repo, used by both envs
```

## Prerequisites

- Two GCP projects, each with billing linked. `ins8-frontend` already exists with
  billing linked. Create `ins8-tasks` the same way:
  ```bash
  gcloud projects create ins8-tasks --name="ins8 tasks"
  gcloud billing projects link ins8-tasks --billing-account=<BILLING_ACCOUNT_ID>
  ```
- A [Neon](https://neon.tech) account and an API key (Neon console -> Account ->
  API keys). Export it, don't put it in a `.tfvars` file:
  ```bash
  export NEON_API_KEY="..."
  ```
- One GCS bucket per project for Terraform state itself (bootstrap problem —
  Terraform can't create the bucket it stores its own state in):
  ```bash
  gcloud storage buckets create gs://ins8-frontend-tfstate \
    --project=ins8-frontend --location=us-east4 --uniform-bucket-level-access
  gcloud storage buckets create gs://ins8-tasks-tfstate \
    --project=ins8-tasks --location=us-east4 --uniform-bucket-level-access
  ```
- `terraform` and `gcloud`, both authenticated:
  ```bash
  gcloud auth application-default login
  ```

## First apply

`envs/ins8-frontend` has no dependency on the backend and can go first:

```bash
cd envs/ins8-frontend
terraform init
terraform apply
```

This deploys the frontend pointed at a public Google-provided placeholder image
(`gcloud/hello`), just so the service exists and gets a stable `*.run.app` URL.
Nothing works yet — that's expected. It also provisions the Artifact Registry repo
and the GitHub Actions deploy identity.

Then `envs/ins8-tasks`, which needs the frontend's URL for `CORS_ALLOWED_ORIGINS`:

```bash
terraform output -raw frontend_url    # from envs/ins8-frontend, still there
cd ../ins8-tasks
cp terraform.tfvars.example terraform.tfvars
# paste the frontend_url output into terraform.tfvars
terraform init
terraform apply
```

This provisions Neon, the Secret Manager secrets, the uploads bucket, the migration
Cloud Run Job, and the backend service (also pointed at the placeholder image until
CI pushes a real one).

## Living without a domain

The frontend and backend are two separate Cloud Run services, so without a shared
registrable domain they're on two different `*.run.app` "sites" (`run.app` is on the
Public Suffix List). The app's session cookie is `SameSite=Lax`
(`ins8-tasks/internal/handler/auth.go`), which browsers refuse to send on a
cross-site `fetch()` — so **logging in through a real browser against the deployed
frontend won't fully work yet**. That's a known, accepted gap right now, not a bug to
chase.

What still works and is worth verifying without a domain:
- The whole CI/CD pipeline: build, push, migrate, deploy.
- The backend directly — health checks, `curl`/Postman against its API, running
  migrations, checking Cloud Run logs.
- The frontend serving its static assets and hitting the backend for anything that
  doesn't depend on the session cookie surviving.

If browser login needs to work before a domain is worth setting up, the fix is
`SameSite=None` (+ `Secure`, already true since Cloud Run is HTTPS-only) on the
session cookie instead of `SameSite=Lax` — deliberately not done here without asking
first, since it removes the app's only current CSRF defense.

Adding a domain later (`app.<domain>`/`api.<domain>`) is the same
`google_cloud_run_domain_mapping` pattern this repo used before the one-project-per-
repo restructure — reintroduce it in whichever env needs it once a domain exists,
rather than paying for the complexity now.

## Getting real images running

The frontend's `VITE_API_BASE_URL` is a **build-time** Vite env var — it gets inlined
into the JS bundle when `npm run build` runs, not read at container startup. That
means the frontend image is specific to whichever backend URL it was built against.

```bash
# 1. Get the backend's URL (stable now, from envs/ins8-tasks' apply above).
cd envs/ins8-tasks
terraform output -raw backend_url

# 2. Build + push the backend image
cd ../../../ins8-tasks   # the application repo, not this infra one
gcloud auth configure-docker us-east4-docker.pkg.dev
docker build -t us-east4-docker.pkg.dev/ins8-tasks/app/backend:latest .
docker push us-east4-docker.pkg.dev/ins8-tasks/app/backend:latest
gcloud run deploy ins8-tasks \
  --project=ins8-tasks --region=us-east4 \
  --image=us-east4-docker.pkg.dev/ins8-tasks/app/backend:latest

# 3. Build the frontend with that backend URL baked in, then push + deploy
cd ../ins8-frontend
docker build --build-arg VITE_API_BASE_URL="<backend_url>/api/v1" \
  -t us-east4-docker.pkg.dev/ins8-frontend/app/frontend:latest .
docker push us-east4-docker.pkg.dev/ins8-frontend/app/frontend:latest
gcloud run deploy ins8-frontend \
  --project=ins8-frontend --region=us-east4 \
  --image=us-east4-docker.pkg.dev/ins8-frontend/app/frontend:latest
```

Terraform's `cloud-run-service` module sets `lifecycle { ignore_changes = [...image] }`
so these `gcloud run deploy` calls (or CI doing the same) don't get reverted by the
next `terraform apply`.

## CI/CD (GitHub Actions)

Both application repos' `.github/workflows/ci.yml` have a "Deploy to Staging" job
(named for what it'll mean once a real staging/prod split exists — right now it's
just "deploy") that runs on every push to `main`: build the image, push it to
Artifact Registry, run pending migrations (backend only, before the new revision
takes traffic), then `gcloud run deploy`. Authentication is via Workload Identity
Federation (`modules/github-ci-identity`) using the official `google-github-actions/auth`
action — no service-account key is stored as a GitHub secret; each workflow trades
its own short-lived OIDC token for GCP credentials scoped to exactly that repository
and branch.

To finish wiring a repo's deploy after its env has been applied:

```bash
terraform output -raw workload_identity_provider
terraform output -raw ci_service_account
```

Create a GitHub **Environment** named `staging` in that repo (Settings ->
Environments -> New environment) and set the variables listed in the comment block
at the bottom of `.github/workflows/ci.yml` — it spells out exactly which output goes
where, as environment **variables** (`vars`), plus `ANTHROPIC_API_KEY` as an
environment (or repository) **secret** for the review-gate job.

The gcloud/WIF command sequence in both workflow files is written from GCP's and
GitHub's own documented flag names, but hasn't been run against a real workflow yet
— watch the first real run closely rather than trusting it blind.

## What's deliberately not here yet

- **A staging/prod split.** One project per repo, one environment, for now — see the
  top of this file. Revisit once there's an actual reason to need it (this was a
  previous, more built-out shape of this repo; it's simpler now on purpose).
- **A custom domain.** See "Living without a domain" above.
- **Rate limiting on `/login`.** Already a known gap per `ins8-tasks/CLAUDE.md` —
  unrelated to this infra, called out here so it isn't forgotten later.

## Notes on specific choices

- **Uploads.** `internal/storage.LocalStorage` writes to `UPLOAD_DIR` on local disk,
  which doesn't exist across Cloud Run instances or restarts. Rather than changing
  application code, `UPLOAD_DIR` points at `/mnt/uploads`, which Cloud Run mounts as a
  GCS bucket via its built-in Cloud Storage FUSE volume support — the app never knows
  the difference.
- **`APP_ENV=production`.** `internal/logging.New` only branches on the literal
  string `"production"` (JSON+info vs text+debug logs) — set unconditionally since
  there's only one environment right now.
- **The uploads bucket has `force_destroy = true`.** Only environment that exists,
  and its data isn't precious yet — revisit if that changes.
- **Both Cloud Run services allow unauthenticated invocation.** That's Cloud Run's
  network-level IAM, separate from the app's own JWT-cookie auth — the frontend is a
  public website and the backend is called directly from the browser, so both need
  `roles/run.invoker` on `allUsers`. Real authorization is still the application's
  job (see `ins8-tasks/CLAUDE.md`'s security rules).
