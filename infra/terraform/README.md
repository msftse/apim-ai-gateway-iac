# Infrastructure — Terraform

A complete Terraform implementation of the Enterprise AI Gateway. The **entire**
APIM control plane (APIs, operations, backends, circuit breakers, the
`aoai-pool`, products, policy fragments + composed policies, the Redis
external-cache binding, and the hosted-agent API) is provisioned declaratively
via the `apim-config` module — so a single `terraform apply` yields a fully
working gateway.

Backends (Azure OpenAI, Content Safety) are reached from APIM via **Managed
Identity** — no model keys are stored or passed to clients.

## Layout

```
infra/terraform/
├── versions.tf            # required_version + providers (azurerm, azapi, random, null)
├── providers.tf           # provider features/auth
├── variables.tf           # all params + deploy_* toggles + existing_* inputs
├── locals.tf              # naming, tags, named values, dependency preconditions
├── main.tf                # resource group + module composition (count-gated)
├── outputs.tf             # outputs (try()-guarded)
├── terraform.tfvars.example
└── modules/
    ├── monitoring/            # Log Analytics + Application Insights
    ├── keyvault/              # Key Vault (RBAC)
    ├── network/               # VNet, subnets, NSG, Redis private DNS
    ├── redis/                 # Azure Managed Redis (azapi, 2025-07-01) + DB
    ├── redis-private-endpoint/# Redis private endpoint + DNS zone group
    ├── content-safety/        # Azure AI Content Safety
    ├── openai/                # Azure OpenAI account + model deployments
    ├── foundry/               # Microsoft Foundry account + project + ACR + models
    ├── apim/                  # API Management + logger + diagnostics
    ├── apim-config/           # APIM control plane: APIs, backends, pool, policies, products, cache binding
    ├── role-assignment/       # APIM identity -> backend RBAC (reusable)
    └── workbook/              # Azure Monitor workbook
```

## Providers & versions

| Provider | Version | Why |
| --- | --- | --- |
| `hashicorp/azurerm` | `~> 4.0` | Primary. Nearly all resources. |
| `azure/azapi` | `~> 2.0` | Azure Managed Redis Enterprise `2025-07-01`, Foundry projects, and the APIM control-plane resources not fully surfaced by azurerm. |
| `hashicorp/random` | `~> 3.6` | Key Vault unique-name suffix; workbook GUID. |
| `hashicorp/null` | `~> 3.2` | Cross-variable dependency preconditions. |

The provider **lock file** (`.terraform.lock.hcl`) **is committed** so every
operator resolves identical provider versions. State (`*.tfstate`) and
`terraform.tfvars` are git-ignored — never commit secrets or state. Local state
is used by default; configure a remote backend for team use.

## Authentication

Uses the standard `azurerm` auth chain — any one of:

- `az login` (developer),
- `ARM_SUBSCRIPTION_ID` / `ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_TENANT_ID` (service principal),
- managed identity (CI runner).

Optionally set `subscription_id` in `.tfvars`; otherwise it falls back to
`ARM_SUBSCRIPTION_ID` / the az CLI context.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set publisher_email / publisher_name and adjust regions,
# resource_prefix, SKUs, and model deployments for your subscription

terraform init
terraform validate
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Static checks with no Azure calls: `terraform init -backend=false && terraform validate`.

> **Provisioning time & cost.** APIM (Developer/Standard) takes 30–45 min to
> provision on first apply. `apply` on APIM, AOAI, Foundry, and Redis **incurs
> real Azure cost**; `plan`/`validate` do not.
>
> **Ordering.** A few APIM control-plane resources depend on backend endpoints
> known only after the backing accounts exist. If a first `apply` reports an
> "Invalid for_each/count argument", apply the base resources first (e.g.
> `-target=module.apim`) and then run a full `apply`.

## Capability feature flags (`enable_*`)

On top of the low-level `deploy_*` component toggles, each `enable_*` flag turns
on a whole **capability** — its Azure resources *and* the matching APIM config:

| Variable | Turns on |
| --- | --- |
| `enable_gateway_api` | `ai-gateway` API + `chat-completions` op + all policy fragments + composed model policy |
| `enable_load_balancing` | `aoai-primary`/`aoai-secondary` backends + circuit breakers + `aoai-pool` (failover) |
| `enable_semantic_cache` | embeddings backend + APIM external cache bound to Redis + cache named values (needs `deploy_redis`) |
| `enable_content_safety` | Content Safety account + backend + `content-safety-on` NV + role assignment |
| `enable_token_limits` | per-tier TPM / daily-quota / max-completion named values |
| `enable_products` | `free`/`standard`/`premium` products + API bindings |
| `enable_hosted_agent` | `hosted-agent` API + agent backends + product bindings (needs `deploy_foundry`) |

## Per-component toggles (`deploy_*`)

Every independently-created component has a boolean (default `true`, except
managed identities). Disabling one uses `count`/`for_each` so the rest stay
deployable, and outputs use `try(...)` to remain valid.

| Variable | Component |
| --- | --- |
| `deploy_resource_group` | Resource group (else use `existing_resource_group_name`) |
| `deploy_virtual_network` | VNet, subnets, NSG |
| `deploy_private_endpoints` | Redis private endpoint |
| `deploy_private_dns` | Private DNS zone + VNet link |
| `deploy_apim` | API Management (+ logger/diagnostics/named values) |
| `deploy_primary_azure_openai` | Primary AOAI account + deployments |
| `deploy_secondary_azure_openai` | Secondary (failover) AOAI account + deployments |
| `deploy_content_safety` | Content Safety (also gated by `content_safety_enabled`) |
| `deploy_redis` | Azure Managed Redis + database |
| `deploy_key_vault` | Key Vault |
| `deploy_log_analytics` | Log Analytics workspace |
| `deploy_application_insights` | Application Insights |
| `deploy_workbook` | Azure Monitor workbook |
| `deploy_diagnostic_settings` | APIM → Log Analytics diagnostic settings |
| `deploy_role_assignments` | APIM identity → backend RBAC |
| `deploy_foundry` | Microsoft Foundry account + project + ACR + models |
| `deploy_managed_identities` | User-assigned identities (default `false`; system-assigned is used otherwise) |

## Reuse existing resources

When a `deploy_*` toggle is `false`, supply the matching existing resource so
dependents can wire up:

| Input | Used when |
| --- | --- |
| `existing_resource_group_name` | `deploy_resource_group = false` |
| `existing_log_analytics_workspace_id` | `deploy_log_analytics = false` |
| `existing_virtual_network_id` | `deploy_virtual_network = false` |
| `existing_apim_subnet_id` | `deploy_virtual_network = false` (APIM injection) |
| `existing_private_link_subnet_id` | `deploy_virtual_network = false` (private endpoints) |
| `existing_redis_dns_zone_id` | `deploy_private_dns = false` |

## Dependency validation (fails `plan` early)

`locals.tf` declares preconditions that reject incompatible combinations, e.g.:

- `deploy_resource_group = false` **requires** `existing_resource_group_name`.
- `deploy_log_analytics = false` **requires** `existing_log_analytics_workspace_id`
  (App Insights, APIM diagnostics, and workbook all need a workspace).
- `deploy_apim` **requires** `deploy_application_insights` (logger/diagnostics bind to it).
- Redis private endpoint **requires** a private-link subnet **and** the Redis
  DNS zone (via `deploy_virtual_network` + `deploy_private_dns`, or the
  `existing_*` inputs).
- `deploy_role_assignments` **requires** `deploy_apim`.

## Outputs

`resource_group_name`, `apim_name`, `apim_gateway_url`, `apim_principal_id`,
`aoai_primary_endpoint`, `aoai_secondary_endpoint`, `redis_host_name`,
`key_vault_name`, `app_insights_connection_string` (sensitive),
`content_safety_endpoint`, `foundry_*`, … All are `try(...)`-guarded so a
toggled-off component yields `null`/`""` rather than an error.
