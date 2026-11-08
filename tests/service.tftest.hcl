# Run with: terraform test
#
# NOTE: `mock_provider` requires Terraform >= 1.7. That is a requirement of this test
# suite only — the module itself still supports terraform >= 1.5 as declared in
# versions.tf, and required_version is deliberately not raised for it.

mock_provider "google" {}

variables {
  project_id = "example-project"
  name       = "api"
  location   = "us-central1"

  # service_account is deliberately left unset here: a run block cannot set a variable
  # back to null, so runs that exercise the default-service-account precondition would
  # otherwise inherit a value from this block. The opt-in is switched off again in the
  # runs that test it.
  allow_default_service_account = true
}

## Defaults --------------------------------------------------------------------

run "defaults_are_not_public" {
  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invoker) == 0
    error_message = "By default the module must not grant roles/run.invoker to allUsers."
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invokers) == 0
    error_message = "By default the module must not grant roles/run.invoker to anyone."
  }
}

run "defaults_set_ingress_and_scaling" {
  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_ALL"
    error_message = "The default ingress must stay INGRESS_TRAFFIC_ALL, matching the Cloud Run API default."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].scaling[0].max_instance_count == 100
    error_message = "max_instance_count must be bounded by default so a traffic spike cannot scale without limit."
  }
}

## Runtime service account ------------------------------------------------------

run "rejects_compute_default_service_account" {
  command = plan

  variables {
    allow_default_service_account = false
  }

  expect_failures = [google_cloud_run_v2_service.this]
}

# The mocked provider invents a value for the computed service_account attribute, so
# this run proves the opt-in by planning successfully at all: without
# allow_default_service_account = true the precondition above aborts the plan.
run "allows_default_service_account_when_explicitly_opted_in" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.this.name == "api"
    error_message = "allow_default_service_account = true must let a plan with no service_account succeed."
  }
}

run "service_account_is_passed_to_the_template" {
  variables {
    service_account               = "run-api@example-project.iam.gserviceaccount.com"
    allow_default_service_account = false
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].service_account == "run-api@example-project.iam.gserviceaccount.com"
    error_message = "Setting service_account must satisfy the precondition and reach the revision template."
  }
}

run "rejects_malformed_service_account" {
  command = plan

  variables {
    service_account = "run-api@example-project.example.com"
  }

  expect_failures = [var.service_account]
}

## Public access ----------------------------------------------------------------

run "allow_unauthenticated_grants_all_users" {
  variables {
    allow_unauthenticated = true
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.invoker[0].member == "allUsers"
    error_message = "allow_unauthenticated = true must grant roles/run.invoker to allUsers."
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.invoker[0].role == "roles/run.invoker"
    error_message = "The public grant must be roles/run.invoker."
  }
}

run "rejects_public_members_smuggled_through_invokers" {
  command = plan

  variables {
    invokers = ["allAuthenticatedUsers"]
  }

  expect_failures = [google_cloud_run_v2_service_iam_member.invokers]
}

run "rejects_all_users_in_invokers_without_opt_in" {
  command = plan

  variables {
    invokers = ["allUsers"]
  }

  expect_failures = [google_cloud_run_v2_service_iam_member.invokers]
}

run "named_invokers_are_granted" {
  variables {
    invokers = [
      "serviceAccount:frontend@example-project.iam.gserviceaccount.com",
      "group:oncall@example.com",
    ]
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invokers) == 2
    error_message = "Each entry of invokers must produce one roles/run.invoker binding."
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.invokers["group:oncall@example.com"].role == "roles/run.invoker"
    error_message = "Named invokers must be granted roles/run.invoker."
  }
}

run "all_users_is_not_managed_twice" {
  variables {
    allow_unauthenticated = true
    invokers              = ["allUsers", "group:oncall@example.com"]
  }

  assert {
    condition     = length(google_cloud_run_v2_service_iam_member.invokers) == 1
    error_message = "allUsers is granted by allow_unauthenticated and must not also be managed by the invokers resource."
  }
}

run "rejects_bare_email_invoker" {
  command = plan

  variables {
    invokers = ["alice@example.com"]
  }

  expect_failures = [var.invokers]
}

## Ingress ----------------------------------------------------------------------

run "ingress_can_be_restricted" {
  variables {
    ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  }

  assert {
    condition     = google_cloud_run_v2_service.this.ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY"
    error_message = "ingress must be passed through to the service."
  }
}

run "rejects_invalid_ingress" {
  command = plan

  variables {
    ingress = "INGRESS_TRAFFIC_NONE"
  }

  expect_failures = [var.ingress]
}

## Environment ------------------------------------------------------------------

run "secret_env_uses_secret_manager_reference" {
  variables {
    env        = { LOG_LEVEL = "info" }
    secret_env = { API_KEY = { secret = "api-key" } }
  }

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].containers[0].env) == 2
    error_message = "env and secret_env must both become container environment variables."
  }

  assert {
    condition = anytrue([
      for e in google_cloud_run_v2_service.this.template[0].containers[0].env :
      e.name == "API_KEY" && length(e.value_source) == 1 && e.value_source[0].secret_key_ref[0].version == "latest"
    ])
    error_message = "secret_env entries must render a secret_key_ref defaulting to the latest version."
  }

  assert {
    condition = anytrue([
      for e in google_cloud_run_v2_service.this.template[0].containers[0].env :
      e.name == "API_KEY" && e.value == null
    ])
    error_message = "A secret-backed variable must not carry a plain-text value."
  }
}

run "rejects_name_defined_in_both_env_and_secret_env" {
  command = plan

  variables {
    env        = { API_KEY = "placeholder" }
    secret_env = { API_KEY = { secret = "api-key" } }
  }

  expect_failures = [google_cloud_run_v2_service.this]
}

## Scaling ----------------------------------------------------------------------

run "rejects_min_greater_than_max" {
  command = plan

  variables {
    min_instance_count = 5
    max_instance_count = 2
  }

  expect_failures = [google_cloud_run_v2_service.this]
}

run "rejects_negative_min_instance_count" {
  command = plan

  variables {
    min_instance_count = -1
  }

  expect_failures = [var.min_instance_count]
}

run "rejects_zero_max_instance_count" {
  command = plan

  variables {
    max_instance_count = 0
  }

  expect_failures = [var.max_instance_count]
}

## Deletion protection ---------------------------------------------------------

run "deletion_protection_defaults_on" {
  assert {
    condition     = google_cloud_run_v2_service.this.deletion_protection == true
    error_message = "deletion_protection must default to true, matching the google provider."
  }
}

run "deletion_protection_can_be_disabled" {
  variables {
    deletion_protection = false
  }

  assert {
    condition     = google_cloud_run_v2_service.this.deletion_protection == false
    error_message = "deletion_protection = false must be passed through so the service can be destroyed."
  }
}

## VPC access -------------------------------------------------------------------

run "vpc_access_is_off_by_default" {
  command = plan

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].vpc_access) == 0
    error_message = "With vpc_access unset the module must not add a vpc_access block, so existing services plan unchanged."
  }
}

run "direct_vpc_egress" {
  command = plan

  variables {
    vpc_access = {
      network      = "projects/example-project/global/networks/main"
      subnetwork   = "projects/example-project/regions/us-central1/subnetworks/run"
      network_tags = ["cloud-run"]
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].egress == "PRIVATE_RANGES_ONLY"
    error_message = "vpc_access.egress must default to PRIVATE_RANGES_ONLY."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].connector == null
    error_message = "Direct VPC egress must not set a connector."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].network_interfaces[0].subnetwork == "projects/example-project/regions/us-central1/subnetworks/run"
    error_message = "vpc_access.subnetwork must reach the network interface."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].network_interfaces[0].tags == tolist(["cloud-run"])
    error_message = "vpc_access.network_tags must reach the network interface."
  }
}

run "vpc_connector" {
  command = plan

  variables {
    vpc_access = {
      connector = "projects/example-project/locations/us-central1/connectors/run"
      egress    = "ALL_TRAFFIC"
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].connector == "projects/example-project/locations/us-central1/connectors/run"
    error_message = "vpc_access.connector must be passed through."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].vpc_access[0].egress == "ALL_TRAFFIC"
    error_message = "vpc_access.egress must be passed through."
  }

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].vpc_access[0].network_interfaces) == 0
    error_message = "A connector must not also produce a Direct VPC egress interface."
  }
}

run "rejects_connector_with_network" {
  command = plan

  variables {
    vpc_access = {
      connector = "projects/example-project/locations/us-central1/connectors/run"
      network   = "main"
    }
  }

  expect_failures = [var.vpc_access]
}

run "rejects_empty_vpc_access" {
  command = plan

  variables {
    vpc_access = {}
  }

  expect_failures = [var.vpc_access]
}

run "rejects_invalid_vpc_egress" {
  command = plan

  variables {
    vpc_access = {
      network = "main"
      egress  = "PRIVATE"
    }
  }

  expect_failures = [var.vpc_access]
}

run "rejects_network_tags_with_connector" {
  command = plan

  variables {
    vpc_access = {
      connector    = "projects/example-project/locations/us-central1/connectors/run"
      network_tags = ["cloud-run"]
    }
  }

  expect_failures = [var.vpc_access]
}

## Probes -----------------------------------------------------------------------

run "probes_are_off_by_default" {
  command = plan

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe) == 0
    error_message = "With liveness_probe unset the module must not add a liveness probe."
  }
}

run "http_startup_probe" {
  command = plan

  variables {
    startup_probe = {
      path                  = "/healthz"
      initial_delay_seconds = 5
      failure_threshold     = 10
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].http_get[0].path == "/healthz"
    error_message = "startup_probe.path must render an http_get probe."
  }

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].tcp_socket) == 0 && length(google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].grpc) == 0
    error_message = "An HTTP probe must not also render tcp_socket or grpc."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].initial_delay_seconds == 5 && google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].failure_threshold == 10
    error_message = "Probe timings must be passed through."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].period_seconds == 10 && google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].timeout_seconds == 1
    error_message = "period_seconds and timeout_seconds must default to the Cloud Run defaults (10 and 1)."
  }
}

run "tcp_startup_probe_uses_container_port" {
  command = plan

  variables {
    port          = 9000
    startup_probe = {}
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].startup_probe[0].tcp_socket[0].port == 9000
    error_message = "A probe with neither path nor grpc_service must be a TCP probe on the container port."
  }
}

run "grpc_liveness_probe" {
  command = plan

  variables {
    liveness_probe = {
      grpc_service   = ""
      port           = 50051
      period_seconds = 30
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe[0].grpc[0].service == ""
    error_message = "grpc_service must render a grpc probe, including the empty whole-server service name."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe[0].grpc[0].port == 50051
    error_message = "liveness_probe.port must reach the grpc probe."
  }

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe[0].http_get) == 0
    error_message = "A gRPC probe must not also render http_get."
  }
}

run "rejects_probe_with_path_and_grpc_service" {
  command = plan

  variables {
    liveness_probe = {
      path         = "/healthz"
      grpc_service = "app"
    }
  }

  expect_failures = [var.liveness_probe]
}

run "rejects_probe_path_without_leading_slash" {
  command = plan

  variables {
    startup_probe = {
      path = "healthz"
    }
  }

  expect_failures = [var.startup_probe]
}

run "rejects_probe_port_out_of_range" {
  command = plan

  variables {
    liveness_probe = {
      port = 70000
    }
  }

  expect_failures = [var.liveness_probe]
}

run "rejects_startup_probe_period_over_240" {
  command = plan

  variables {
    startup_probe = {
      period_seconds = 300
    }
  }

  expect_failures = [var.startup_probe]
}

run "accepts_liveness_probe_period_over_240" {
  command = plan

  variables {
    liveness_probe = {
      path           = "/healthz"
      period_seconds = 300
    }
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].containers[0].liveness_probe[0].period_seconds == 300
    error_message = "Liveness probes allow period_seconds up to 3600."
  }
}

run "rejects_probe_timeout_longer_than_period" {
  command = plan

  variables {
    liveness_probe = {
      timeout_seconds = 20
      period_seconds  = 10
    }
  }

  expect_failures = [var.liveness_probe]
}
