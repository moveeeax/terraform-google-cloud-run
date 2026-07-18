# terraform-google-cloud-run

Terraform module that manages a [Google Cloud](https://cloud.google.com/)
Cloud Run service (`google_cloud_run_v2_service`). It deploys a container with
configurable scaling, resources and environment variables, and can optionally
allow public unauthenticated access.

## Usage

```hcl
module "cloud_run" {
  source = "github.com/cybercapybara/terraform-google-cloud-run"

  project_id = var.project_id
  name       = "api"
  location   = "us-central1"
  image      = "us-docker.pkg.dev/my-project/api/app:latest"

  env = {
    LOG_LEVEL = "info"
  }

  allow_unauthenticated = true
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| google    | >= 5.0   |

## Inputs

| Name                    | Description                                                | Type          | Default                                            | Required |
|-------------------------|------------------------------------------------------------|---------------|----------------------------------------------------|:--------:|
| `project_id`            | ID of the project in which to create the service.          | `string`      | n/a                                                |   yes    |
| `name`                  | Name of the Cloud Run service.                             | `string`      | n/a                                                |   yes    |
| `location`              | Region in which to deploy the service.                     | `string`      | n/a                                                |   yes    |
| `image`                 | Container image to deploy.                                 | `string`      | `"us-docker.pkg.dev/cloudrun/container/hello"`     |    no    |
| `port`                  | Container port the service listens on.                     | `number`      | `8080`                                             |    no    |
| `cpu`                   | CPU limit for the container.                               | `string`      | `"1"`                                              |    no    |
| `memory`                | Memory limit for the container.                            | `string`      | `"512Mi"`                                          |    no    |
| `min_instance_count`    | Minimum number of container instances.                     | `number`      | `0`                                                |    no    |
| `max_instance_count`    | Maximum number of container instances.                     | `number`      | `100`                                              |    no    |
| `env`                   | Environment variables passed to the container.             | `map(string)` | `{}`                                               |    no    |
| `allow_unauthenticated` | Whether to allow public unauthenticated invocations.       | `bool`        | `false`                                            |    no    |
| `labels`                | Labels applied to the service.                             | `map(string)` | `{}`                                               |    no    |

## Outputs

| Name   | Description                             |
|--------|-----------------------------------------|
| `id`   | Identifier of the Cloud Run service.   |
| `name` | Name of the Cloud Run service.         |
| `uri`  | Public URI of the Cloud Run service.   |

## License

[MIT](LICENSE)
