# Infrastructure

Terraform for both `tasks` (backend) and `ins8-frontend` (frontend), deployed to
Google Cloud Run, with Postgres on [Neon](https://neon.tech)'s free tier instead of
Cloud SQL (Cloud SQL has no perpetual free tier — smallest instance still bills
continuously).

Two fully separate GCP projects — staging and prod each get their own project, own
Terraform state, own Neon project, own everything. A mistake in staging (bad IAM
binding, runaway resource) can't reach prod.

```
envs/
  staging/    root module for the staging project — own backend "gcs" state
  prod/       root module for the prod project — own backend "gcs" state
modules/
  environment/       one environment's full stack: APIs, Artifact Registry, Neon
                     project, secrets, uploads bucket, service accounts, and the
                     two Cloud Run services
  cloud-run-service/ generic Cloud Run v2 service wrapper, used for both frontend
                     and backend
```

## Prerequisites

- Two GCP projects, each with billing linked: e.g. `seedtech-staging`, `seedtech-prod`.
  Terraform does not create the projects themselves (that needs org/billing IDs this
  repo has no way to know) — create them first:
  ```bash
  gcloud projects create seedtech-staging --name="SeedTech Staging"
  gcloud billing projects link seedtech-staging --billing-account=<BILLING_ACCOUNT_ID>
  # repeat for seedtech-prod
  ```
- A [Neon](https://neon.tech) account and an API key (Neon console -> Account ->
  API keys). Export it, don't put it in a `.tfvars` file:
  ```bash
  export NEON_API_KEY="..."
  ```
- One GCS bucket per environment for Terraform state itself (bootstrap problem —
  Terraform can't create the bucket it stores its own state in):
  ```bash
  gcloud storage buckets create gs://seedtech-tfstate-staging \
    --project=seedtech-staging --location=us-east4 --uniform-bucket-level-access
  gcloud storage buckets create gs://seedtech-tfstate-prod \
    --project=seedtech-prod --location=us-east4 --uniform-bucket-level-access
  ```
- `terraform` and `gcloud`, both authenticated:
  ```bash
  gcloud auth application-default login
  ```
- **A domain you own** (e.g. `seedtech.dev`), verified in
  [Google Search Console](https://search.google.com/search-console) under the same
  Google identity you just authenticated with. This is required, not optional: the
  frontend and backend are deployed as two separate Cloud Run services, and Cloud
  Run's default `*.run.app` URLs put every service on its own "site" (`run.app` is on
  the Public Suffix List) — the app's session cookie is `SameSite=Lax`
  (`tasks/internal/handler/auth.go`), which browsers refuse to send on cross-site
  `fetch()` calls. Mapping both services to subdomains of one registrable domain
  (`app.<domain>` / `api.<domain>` for prod, `app.staging.<domain>` /
  `api.staging.<domain>` for staging) makes them same-site again, with no application
  code changes. `google_cloud_run_domain_mapping` will fail at apply time if the
  domain isn't verified first.

## First apply (per environment)

```bash
cd envs/staging   # or envs/prod
cp terraform.tfvars.example terraform.tfvars   # fill in project_id and domain
terraform init
terraform apply
```

This first apply deploys both Cloud Run services pointed at a public Google-provided
placeholder image (`gcloud/hello`), just so they exist and get a stable URL. Nothing
works yet — that's expected. It also provisions Neon, Secret Manager secrets, the
uploads bucket, service accounts, the Artifact Registry repo, and the two domain
mappings.

Once it completes, add the DNS records it's waiting on:

```bash
terraform output -json dns_records_needed
```

Add each returned record (type + name + rrdata) at whatever DNS provider hosts your
domain. Cloud Run won't finish issuing the managed TLS cert until they resolve — this
can take anywhere from a couple of minutes to a few hours depending on your DNS
provider's propagation and Google's own cert issuance. Check status with:

```bash
gcloud run domain-mappings describe --domain=app.staging.<your-domain> \
  --project=seedtech-staging --region=us-east4
```

## Getting real images running

The frontend's `VITE_API_BASE_URL` is a **build-time** Vite env var — it gets inlined
into the JS bundle when `npm run build` runs, not read at container startup. That
means the frontend image itself is environment-specific (a staging build and a prod
build are different images, because they point at different backend URLs), and it
also means Terraform can't wire it up automatically the way it wires
`CORS_ALLOWED_ORIGINS` (which the backend *does* read at runtime, so Terraform sets it
straight from `module.frontend.uri`).

Practical order for a brand-new environment:

```bash
# 1. Get the backend's custom-domain URL (stable now, from the apply above).
#    Use THIS, not `terraform output -raw backend_url` (the raw *.run.app one) —
#    the frontend must call the backend at its custom domain, or the same
#    cross-site cookie problem the domain mapping was added to solve comes
#    right back for anyone actually using the deployed app.
terraform output -raw backend_https_url

# 2. Build + push the backend image
cd ../../../tasks
gcloud auth configure-docker us-east4-docker.pkg.dev
docker build -t us-east4-docker.pkg.dev/seedtech-staging/app/backend:latest .
docker push us-east4-docker.pkg.dev/seedtech-staging/app/backend:latest
gcloud run deploy seedtech-staging-backend \
  --project=seedtech-staging --region=us-east4 \
  --image=us-east4-docker.pkg.dev/seedtech-staging/app/backend:latest

# 3. Build the frontend with that backend URL baked in, then push + deploy
cd ../ins8-frontend
docker build --build-arg VITE_API_BASE_URL="<backend_https_url>/api/v1" \
  -t us-east4-docker.pkg.dev/seedtech-staging/app/frontend:latest .
docker push us-east4-docker.pkg.dev/seedtech-staging/app/frontend:latest
gcloud run deploy seedtech-staging-frontend \
  --project=seedtech-staging --region=us-east4 \
  --image=us-east4-docker.pkg.dev/seedtech-staging/app/frontend:latest
```

Visit the app at `terraform output -raw frontend_https_url`, not the raw `*.run.app`
frontend URL — same reasoning as step 1.

Terraform's `cloud-run-service` module sets `lifecycle { ignore_changes = [...image] }`
on both services specifically so these `gcloud run deploy` calls (or a CI pipeline
doing the same) don't get reverted by the next `terraform apply`.

## CI/CD (Bitbucket Pipelines, staging only so far)

Both `tasks/bitbucket-pipelines.yml` and `ins8-frontend/bitbucket-pipelines.yml` have
a "Deploy to Staging" step that runs on every push to `main`: build the image, push
it to Artifact Registry, run pending migrations (backend only, before the new
revision takes traffic), then `gcloud run deploy`. Authentication is via Workload
Identity Federation (`modules/environment/ci.tf`) — no service-account key is stored
in Bitbucket; each pipeline trades its own short-lived OIDC token for GCP credentials
scoped to exactly that repository and branch.

Prod deploys are **not** wired up — `ci_deploy_branch` has no default for prod on
purpose (see `modules/environment/variables.tf`), so this doesn't silently let every
staging merge also assume a prod deploy identity. Building that out is future work,
once staging has proven itself.

To finish wiring a fresh staging environment after `terraform apply`:

1. Get the three Bitbucket UUIDs `terraform.tfvars` needs (`bitbucket_workspace_uuid`,
   `backend_repository_uuid`, `frontend_repository_uuid`) from each repo's
   **Repository Settings -> OpenID Connect** page, apply, then:
   ```bash
   terraform output -raw workload_identity_provider
   terraform output -raw ci_backend_service_account
   terraform output -raw ci_frontend_service_account
   terraform output -raw migrate_job_name
   terraform output -raw backend_https_url
   ```
2. In each repo, create a Bitbucket **Deployment environment** named `staging`
   (Repository settings -> Deployments) and set the variables listed in the comment
   block at the bottom of that repo's `bitbucket-pipelines.yml` — it spells out
   exactly which output goes where.

The gcloud/WIF command sequence in both pipeline files is written from GCP's and
Bitbucket's own documented flag names, but — like the existing Claude Code Review
Gate step — hasn't been run against a real pipeline yet. Watch the first real run
closely rather than trusting it blind.

## What's deliberately not here yet

- **Prod CI/CD.** See above.
- **Rate limiting on `/login`.** Already a known gap per `tasks/CLAUDE.md` — unrelated
  to this infra, called out here so it isn't forgotten during a prod launch.

## Notes on specific choices

- **Uploads.** `internal/storage.LocalStorage` writes to `UPLOAD_DIR` on local disk,
  which doesn't exist across Cloud Run instances or restarts. Rather than changing
  application code, `UPLOAD_DIR` points at `/mnt/uploads`, which Cloud Run mounts as a
  GCS bucket via its built-in Cloud Storage FUSE volume support — the app never knows
  the difference.
- **`APP_ENV=production` in both staging and prod.** `internal/logging.New` only
  branches on the literal string `"production"` (JSON+info vs text+debug logs).
  Staging is meant to behave like prod code-path-wise, so both get the same value;
  the Terraform `environment` variable (`"staging"`/`"prod"`) is what actually drives
  resource naming and instance-count differences.
- **Custom domains are required, not a nice-to-have.** See the Prerequisites section
  above — this isn't about vanity URLs, it's the only way the existing
  `SameSite=Lax` session cookie survives two separate Cloud Run services. The
  alternative (relaxing the cookie to `SameSite=None`) would remove the app's only
  current CSRF defense, so it wasn't done here without asking first.
- **Both Cloud Run services allow unauthenticated invocation.** That's Cloud Run's
  network-level IAM, separate from the app's own JWT-cookie auth — the frontend is a
  public website and the backend is called directly from the browser, so both need
  `roles/run.invoker` on `allUsers`. Real authorization is still the application's job
  (see `tasks/CLAUDE.md`'s security rules).
