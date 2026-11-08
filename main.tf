locals {
  # Special IAM members that make an invoker grant public. allUsers is anyone on the
  # internet; allAuthenticatedUsers is any Google account anywhere, including accounts
  # outside your organization.
  public_members = ["allUsers", "allAuthenticatedUsers"]

  # allUsers is already granted by the allow_unauthenticated resource below; drop it
  # here so the same binding is not managed by two resources.
  invokers = toset([
    for member in var.invokers : member
    if !(var.allow_unauthenticated && member == "allUsers")
  ])
}

resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  name     = var.name
  location = var.location
  labels   = var.labels
  ingress  = var.ingress

  # google >= 6.0 defaults this to true, which makes `terraform destroy` (and any
  # change that forces replacement) fail until it is turned off and applied.
  deletion_protection = var.deletion_protection

  template {
    # Leaving this null makes Cloud Run fall back to the Compute Engine default
    # service account, which holds roles/editor on the whole project. The
    # precondition below forces that to be a deliberate choice.
    service_account = var.service_account

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    # Outbound access to a VPC, either through Direct VPC egress (network and/or
    # subnetwork) or through a Serverless VPC Access connector. Omitted entirely when
    # vpc_access is null, so services without it plan exactly as before.
    dynamic "vpc_access" {
      for_each = var.vpc_access == null ? [] : [var.vpc_access]
      content {
        connector = vpc_access.value.connector
        egress    = vpc_access.value.egress

        dynamic "network_interfaces" {
          for_each = vpc_access.value.connector == null ? [vpc_access.value] : []
          content {
            network    = network_interfaces.value.network
            subnetwork = network_interfaces.value.subnetwork
            tags       = length(network_interfaces.value.network_tags) > 0 ? network_interfaces.value.network_tags : null
          }
        }
      }
    }

    containers {
      image = var.image

      ports {
        container_port = var.port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret Manager references. The value is resolved by Cloud Run at runtime and
      # never stored in the service spec or in Terraform state.
      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }

      # Health probes. The probe kind follows from the input: grpc_service set means a
      # gRPC health check, path set means an HTTP GET, neither means a TCP connect.
      # With startup_probe null the block is omitted and Cloud Run keeps its own
      # default TCP startup probe; with liveness_probe null there is none.
      dynamic "startup_probe" {
        for_each = var.startup_probe == null ? [] : [var.startup_probe]
        content {
          initial_delay_seconds = startup_probe.value.initial_delay_seconds
          timeout_seconds       = startup_probe.value.timeout_seconds
          period_seconds        = startup_probe.value.period_seconds
          failure_threshold     = startup_probe.value.failure_threshold

          dynamic "http_get" {
            for_each = startup_probe.value.grpc_service == null && startup_probe.value.path != null ? [startup_probe.value] : []
            content {
              path = http_get.value.path
              port = http_get.value.port
            }
          }

          dynamic "grpc" {
            for_each = startup_probe.value.grpc_service != null ? [startup_probe.value] : []
            content {
              service = grpc.value.grpc_service
              port    = grpc.value.port
            }
          }

          dynamic "tcp_socket" {
            for_each = startup_probe.value.grpc_service == null && startup_probe.value.path == null ? [startup_probe.value] : []
            content {
              # The provider requires a port for liveness TCP probes; fall back to
              # the container port for both kinds.
              port = coalesce(tcp_socket.value.port, var.port)
            }
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = var.liveness_probe == null ? [] : [var.liveness_probe]
        content {
          initial_delay_seconds = liveness_probe.value.initial_delay_seconds
          timeout_seconds       = liveness_probe.value.timeout_seconds
          period_seconds        = liveness_probe.value.period_seconds
          failure_threshold     = liveness_probe.value.failure_threshold

          dynamic "http_get" {
            for_each = liveness_probe.value.grpc_service == null && liveness_probe.value.path != null ? [liveness_probe.value] : []
            content {
              path = http_get.value.path
              port = http_get.value.port
            }
          }

          dynamic "grpc" {
            for_each = liveness_probe.value.grpc_service != null ? [liveness_probe.value] : []
            content {
              service = grpc.value.grpc_service
              port    = grpc.value.port
            }
          }

          dynamic "tcp_socket" {
            for_each = liveness_probe.value.grpc_service == null && liveness_probe.value.path == null ? [liveness_probe.value] : []
            content {
              # The provider requires a port for liveness TCP probes; fall back to
              # the container port for both kinds.
              port = coalesce(tcp_socket.value.port, var.port)
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.service_account != null || var.allow_default_service_account
      error_message = "No service_account was set for Cloud Run service \"${var.name}\". Cloud Run would then run it as the Compute Engine default service account, which holds roles/editor on the entire project, so any code in the container could read and modify almost every resource in it. Set service_account to a dedicated service account, or set allow_default_service_account = true to accept the default."
    }

    precondition {
      condition     = var.min_instance_count <= var.max_instance_count
      error_message = "min_instance_count (${var.min_instance_count}) must be less than or equal to max_instance_count (${var.max_instance_count})."
    }

    precondition {
      condition     = length(setintersection(keys(var.env), keys(var.secret_env))) == 0
      error_message = "These names appear in both env and secret_env: ${join(", ", sort(setintersection(keys(var.env), keys(var.secret_env))))}. A container environment variable can only be defined once."
    }
  }
}

# Public, unauthenticated access. Kept as a separate resource with `count` so that its
# state address is unchanged for existing consumers.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Named principals allowed to invoke the service. This is the authenticated
# alternative to allow_unauthenticated; it exists so that reaching the service does not
# require going all the way to allUsers.
resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = local.invokers

  project  = var.project_id
  location = var.location
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value

  lifecycle {
    precondition {
      condition     = var.allow_unauthenticated || !contains(local.public_members, each.value)
      error_message = "Refusing to grant roles/run.invoker to ${each.value}: that publishes the service to the internet. Set allow_unauthenticated = true if that is intended."
    }
  }
}
