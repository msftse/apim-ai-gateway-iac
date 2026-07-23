# APIM AI Gateway — Infrastructure as Code (Terraform)

Self-contained Terraform that stands up the **Enterprise AI Gateway** infrastructure
exactly as the live `eaig-demo` environment, **excluding** the web UI and the MCP
web-search backend page.

## What it provisions

- **Azure API Management** (Developer SKU) with system-assigned identity
- **APIM control plane** (all as code — no post-deploy scripts):
  - Named values (single source of truth in `locals.tf`)
  - Policy fragments + composed API policies (raw XML in `apim/policies/`)
  - `ai-gateway` API (chat-completions) and `hosted-agent` API (responses)
  - Backends: `aoai-primary`, `aoai-secondary`, `embeddings-backend`,
    `content-safety-backend`, per-tier agent backends + circuit breakers
  - `aoai-pool` priority load-balanced pool (automatic failover)
  - Products: free / standard / premium + API bindings
  - External cache bound to Azure Managed Redis (semantic cache)
- **Azure OpenAI** primary + secondary accounts with model deployments
  (incl. `text-embedding-3-small` for the semantic cache embeddings)
- **Microsoft Foundry** primary + secondary accounts (hosted agents)
- **Azure Managed Redis** (Enterprise) + private endpoint
- **Azure AI Content Safety**
- **Networking** (VNet, subnets, NSG, private DNS)
- **Key Vault**
- **Monitoring** (Log Analytics, Application Insights, Workbook)
- **RBAC** role assignments (APIM identity → AOAI / Content Safety / Foundry)

## Excluded (by design)

- The web UI / Container Apps (`deploy_apps = false`)
- The MCP web-search backend page (`enable_mcp_web_search = false`)

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
az login
export ARM_SUBSCRIPTION_ID=<your-subscription-id>
terraform init
terraform plan   -var-file=terraform.tfvars
terraform apply  -var-file=terraform.tfvars
```

Edit `terraform.tfvars` for region, prefix, SKU, and publisher details.
