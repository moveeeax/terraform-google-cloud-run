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
  source = "github.com/moveeeax/terraform-google-cloud-run"

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

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| google    | >= 5.0   |

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
