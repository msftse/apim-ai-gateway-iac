# `apim/policies`

APIM policy XML — the heart of the gateway's runtime governance. Organized into
three folders by scope:

```
model/
  api-policy.xml            # composed API policy for the AOAI model gateway (/ai)
  fragments/                # model-only fragments
    jwt-validation.xml
    request-validation.xml
    model-alias-resolution.xml
    backend-routing.xml
agent/
  api-policy.xml            # composed API policy for the Foundry Hosted Agent (/agent)
  fragments/                # (agent-only fragments — none today)
shared/
  fragments/                # fragments included by BOTH API policies
    correlation-id.xml
    consumer-context.xml
    token-limit.xml
    content-safety.xml
    semantic-cache-lookup.xml
    semantic-cache-store.xml
    token-metrics.xml
    structured-logging.xml
```

Fragments provide reusable governance: token rate limiting (`llm-token-limit`),
semantic caching (`llm-semantic-cache-lookup/store`), content safety
(`llm-content-safety`), token metric emission (`llm-emit-token-metric`),
structured request logging (`<trace>`), Managed Identity auth, and backend
routing.

## Fragment ids vs. file paths

Each fragment uploads to APIM under the flat id `ai-<name>` (e.g.
`shared/fragments/content-safety.xml` → `ai-content-safety`). The `fragment-id`
namespace is **per-APIM-instance and independent of local folder**, so moving a
file between folders does not change its id — only `scripts/configure-apim.sh`'s
file→id map needs the new path. Both API policies reference fragments only by id
via `<include-fragment fragment-id="ai-..." />`.

Policy expressions embed C# and must be valid XML. Run
`scripts/escape-policy-expressions.py` (it discovers XML recursively) before
upload; the `tests/integration/policy-xml.test.ts` suite enforces
well-formedness and the id↔file mapping in CI.
