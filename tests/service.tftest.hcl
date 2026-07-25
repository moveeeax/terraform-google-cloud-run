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
