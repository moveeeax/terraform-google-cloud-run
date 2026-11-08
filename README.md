# terraform-google-cloud-run

Terraform module that manages a [Google Cloud](https://cloud.google.com/)
Cloud Run service (`google_cloud_run_v2_service`). It deploys a container with
configurable scaling, resources, ingress and environment variables, and can
optionally allow public unauthenticated access.

The module is deliberately private by default: it does not grant
`roles/run.invoker` to anyone unless you ask it to, and it refuses to run your
container as the over-privileged Compute Engine default service account.

## Usage

```hcl
resource "google_service_account" "api" {
  project    = var.project_id
  account_id = "api-run"
}

module "cloud_run" {
  source = "github.com/moveeeax/terraform-google-cloud-run?ref=v1.0.0"

  project_id      = var.project_id
  name            = "api"
  location        = "us-central1"
  image           = "us-docker.pkg.dev/my-project/api/app:latest"
  service_account = google_service_account.api.email

  env = {
    LOG_LEVEL = "info"
  }

  # Resolved by Cloud Run at runtime; never stored in state.
  secret_env = {
    API_KEY = { secret = "api-key" }
  }

  # Only these principals may call the service.
  invokers = [
    "serviceAccount:frontend@my-project.iam.gserviceaccount.com",
  ]
}
```

A runnable example lives in [`examples/basic`](examples/basic).

### Runtime service account

Cloud Run runs a service as the Compute Engine default service account unless
you say otherwise. That account holds `roles/editor` on the whole project, so
anything running in the container — including a compromised dependency — can
read and modify almost every resource in it.

Set `service_account` to a dedicated account granted only the roles the service
needs. If you genuinely want the default account, set
`allow_default_service_account = true`; otherwise the plan fails with an
explanation.

### Public access

`allow_unauthenticated = true` grants `roles/run.invoker` to `allUsers`, which
puts the service on the open internet with no authentication whatsoever. Prefer
`invokers` to name the principals that may call the service. `allUsers` and
`allAuthenticatedUsers` are rejected in `invokers` unless
`allow_unauthenticated = true`, so public access is always an explicit decision.

`ingress` controls which traffic can reach the service at the network layer and
is independent of IAM. `INGRESS_TRAFFIC_INTERNAL_ONLY` restricts it to VPC and
internal traffic; the default `INGRESS_TRAFFIC_ALL` accepts requests from the
internet, which still need `roles/run.invoker` unless the service is public.

### Secrets

Values in `env` are stored in clear text in the service spec and in Terraform
state. Put credentials, tokens and keys in `secret_env` instead — Cloud Run
resolves them from Secret Manager at runtime. Grant the service's runtime
service account `roles/secretmanager.secretAccessor` on each secret.

### VPC access

By default the service has no route into your VPC, so it cannot reach Cloud
SQL over private IP, Memorystore or an internal load balancer. `vpc_access`
adds one, in one of two modes:

```hcl
# Direct VPC egress: instances get IPs from the subnetwork.
vpc_access = {
  subnetwork   = "projects/my-project/regions/us-central1/subnetworks/run"
  network_tags = ["cloud-run"]
}

# Or a Serverless VPC Access connector you manage elsewhere.
vpc_access = {
  connector = "projects/my-project/locations/us-central1/connectors/run"
}
```

Set `connector`, or `network` and/or `subnetwork`, never both. `egress` defaults
to `PRIVATE_RANGES_ONLY`, which sends only private-range traffic through the
VPC; set `ALL_TRAFFIC` to route everything, for example through Cloud NAT for a
static outbound IP. `network_tags` work only with Direct VPC egress and are
useful for targeting firewall rules.

### Health probes

`startup_probe` holds traffic back until the container is ready, and
`liveness_probe` restarts an instance that stops responding. The probe kind
follows from what you set: `path` for an HTTP GET, `grpc_service` for a gRPC
health check (`""` checks the whole server), neither for a TCP connect. `port`
defaults to the container port.

```hcl
# A slow-starting app: allow up to 10 s initial delay + 30 x 5 s to come up.
startup_probe = {
  path                  = "/healthz"
  initial_delay_seconds = 10
  period_seconds        = 5
  failure_threshold     = 30
}

liveness_probe = {
  path           = "/healthz"
  period_seconds = 30
}
```

Both default to `null`. With `startup_probe` unset Cloud Run keeps its own
default TCP startup probe on the container port; with `liveness_probe` unset
there is no liveness check. For most HTTP services an HTTP startup probe on a
readiness endpoint plus an HTTP liveness probe is a reasonable setup.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| google    | >= 6.0, < 9.0 |

The floor is 6.0 because the module sets `deletion_protection` on
`google_cloud_run_v2_service`, a field that provider release added (with a
default of `true`). CI validates and tests against 6.0.0 and the latest 8.x
release; 9.x is excluded until it has been tested.

## Deletion protection

`deletion_protection` defaults to `true`, as in the google provider since 6.0:
Terraform refuses to destroy or replace the service. To remove it, set
`deletion_protection = false`, run `terraform apply`, and then
`terraform destroy`.

The test suite under [`tests/`](tests) additionally needs Terraform >= 1.7 for
`mock_provider`. That is a requirement of the tests only.

## Inputs

| Name                            | Description                                                                | Type                                                          | Default                                        | Required |
|---------------------------------|----------------------------------------------------------------------------|---------------------------------------------------------------|------------------------------------------------|:--------:|
| `project_id`                    | ID of the project in which to create the service.                          | `string`                                                      | n/a                                            |   yes    |
| `name`                          | Name of the Cloud Run service.                                             | `string`                                                      | n/a                                            |   yes    |
| `location`                      | Region in which to deploy the service.                                     | `string`                                                      | n/a                                            |   yes    |
| `image`                         | Container image to deploy.                                                 | `string`                                                      | `"us-docker.pkg.dev/cloudrun/container/hello"` |    no    |
| `service_account`               | Email of the service account the container runs as.                        | `string`                                                      | `null`                                         |    no    |
| `allow_default_service_account` | Accept the Compute Engine default service account (`roles/editor`).        | `bool`                                                        | `false`                                        |    no    |
| `ingress`                       | Which network traffic may reach the service.                               | `string`                                                      | `"INGRESS_TRAFFIC_ALL"`                        |    no    |
| `port`                          | Container port the service listens on.                                     | `number`                                                      | `8080`                                         |    no    |
| `cpu`                           | CPU limit for the container.                                               | `string`                                                      | `"1"`                                          |    no    |
| `memory`                        | Memory limit for the container.                                            | `string`                                                      | `"512Mi"`                                      |    no    |
| `min_instance_count`            | Minimum number of container instances.                                     | `number`                                                      | `0`                                            |    no    |
| `max_instance_count`            | Maximum number of container instances.                                     | `number`                                                      | `100`                                          |    no    |
| `env`                           | Plain-text environment variables passed to the container.                  | `map(string)`                                                 | `{}`                                           |    no    |
| `secret_env`                    | Environment variables sourced from Secret Manager.                         | `map(object({ secret = string, version = optional(string) }))` | `{}`                                           |    no    |
| `allow_unauthenticated`         | Grant `roles/run.invoker` to `allUsers` (public internet access).           | `bool`                                                        | `false`                                        |    no    |
| `invokers`                      | IAM principals granted `roles/run.invoker` on the service.                 | `list(string)`                                                | `[]`                                           |    no    |
| `labels`                        | Labels applied to the service.                                             | `map(string)`                                                 | `{}`                                           |    no    |
| `deletion_protection`           | Prevent Terraform from destroying or replacing the service. Set `false` and apply before destroying. | `bool` | `true` | no |
| `vpc_access`                    | Direct VPC egress (`network`, `subnetwork`, `network_tags`) or a VPC connector (`connector`), plus `egress` (`PRIVATE_RANGES_ONLY` or `ALL_TRAFFIC`). | `object({ network = optional(string), subnetwork = optional(string), connector = optional(string), egress = optional(string, "PRIVATE_RANGES_ONLY"), network_tags = optional(list(string), []) })` | `null` | no |
| `startup_probe`                 | Startup probe: `path` (HTTP), `grpc_service` (gRPC) or neither (TCP), plus `port` and timings. | `object({ path = optional(string), port = optional(number), grpc_service = optional(string), initial_delay_seconds = optional(number, 0), timeout_seconds = optional(number, 1), period_seconds = optional(number, 10), failure_threshold = optional(number, 3) })` | `null` | no |
| `liveness_probe`                | Liveness probe, same shape as `startup_probe`.                             | same as `startup_probe`                                       | `null`                                         |    no    |

## Outputs

| Name   | Description                             |
|--------|-----------------------------------------|
| `id`   | Identifier of the Cloud Run service.   |
| `name` | Name of the Cloud Run service.         |
| `uri`  | Public URI of the Cloud Run service.   |

## Tests

```
terraform test
```

## License

[MIT](LICENSE)
