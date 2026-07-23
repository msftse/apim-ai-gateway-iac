# APIM AI Gateway 
Self-contained Terraform that stands up an **Enterprise AI Gateway** built on
Azure API Management: a governed, load-balanced, cache-enabled front door for
Azure OpenAI and Microsoft Foundry hosted agents. The entire APIM control plane
(named values, policies, APIs, backends, products, cache binding) is managed as
code — a single `terraform apply` yields a fully working gateway.

## What it provisions

- **Azure API Management** with a system-assigned managed identity
- **APIM control plane** (all as code):
  - Named values (single source of truth in `locals.tf`)
  - Policy fragments + composed API policies (raw XML in `apim/policies/`)
  - `ai-gateway` API (chat-completions) and `hosted-agent` API (responses)
  - Backends: `aoai-primary`, `aoai-secondary`, `embeddings-backend`,
    `content-safety-backend`, per-tier agent backends + circuit breakers
  - `aoai-pool` priority load-balanced pool (automatic failover)
  - Products: free / standard / premium + API bindings
  - External cache bound to Azure Managed Redis (semantic cache)
- **Azure OpenAI** primary + secondary accounts with model deployments
  (incl. `text-embedding-3-small` for the semantic-cache embeddings)
- **Microsoft Foundry** primary + secondary accounts (hosted agents)
- **Azure Managed Redis** (Enterprise) + private endpoint
- **Azure AI Content Safety**
- **Networking** (VNet, subnets, NSG, private DNS)
- **Key Vault**
- **Monitoring** (Log Analytics, Application Insights, Workbook)
- **RBAC** role assignments (APIM identity → AOAI / Content Safety / Foundry)

Every component is toggle-driven. Turn a capability on/off with the
`enable_*` flags, and create/skip/reuse individual resources with the
`deploy_*` and `existing_*` inputs. See `infra/terraform/variables.tf` and
`terraform.tfvars.example` for the full list with descriptions.

## Layout

```
infra/terraform/    root module + modules/
apim/policies/      policy fragments + API policy XML
apim/products/      product definitions
monitoring/         Azure Monitor workbook JSON
```

## Deploy

```bash
cd infra/terraform

# 1. Authenticate
az login
export ARM_SUBSCRIPTION_ID=<your-subscription-id>

# 2. Provide your values (terraform.tfvars is git-ignored)
cp terraform.tfvars.example terraform.tfvars
#   edit terraform.tfvars: set publisher_email / publisher_name and adjust
#   regions, resource_prefix, SKUs, and model deployments for your subscription

# 3. Deploy
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Notes

- **Regions / capacity.** All regions are configurable (`location`,
  `secondary_location`, `redis_location`, `foundry_secondary_location`). Choose
  regions that have quota and capacity for your selected SKUs and for the model
  versions listed in `primary_deployments` / `foundry_model_deployments`.
- **Provisioning order.** Several APIM control-plane resources depend on backend
  endpoints that are only known after the backing accounts exist. If a first
  `apply` reports "Invalid for_each/count argument", apply the base resources
  first (e.g. `-target=module.apim`) and then run a full `apply`.
- **CORS.** The gateway/agent CORS policy uses `allow-credentials=true`, so
  `web_allowed_origin` must be a single explicit origin (a wildcard `*` is
  rejected). Set it to your client application URL.
- **Secrets.** No secrets are stored in this repository. Provider auth comes
  from the Azure CLI / environment; `terraform.tfvars` is git-ignored.
