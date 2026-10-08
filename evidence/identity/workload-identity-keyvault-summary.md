# AKS Workload Identity and Key Vault Evidence

Date: 2026-10-07

## Architecture validated

AKS Pod
→ Kubernetes Service Account
→ AKS OIDC Federation
→ User Assigned Managed Identity
→ Private Key Vault Endpoint
→ Azure RBAC
→ Secret Retrieval

## Validated controls

- AKS OIDC enabled
- AKS Workload Identity enabled
- Service account: aks-platform-demo-sa
- UAMI: uami-aks-workload-australiaeast-001
- Key Vault: kv-aks-app-ae-001
- Key Vault public network access disabled
- Key Vault resolved privately from AKS
- Federated token successfully exchanged with Entra ID
- Azure Policy denied non-compliant secret creation
- Secret recreated with policy-compliant expiration
- Key Vault Secrets Officer removed
- Final permission: Key Vault Secrets User
- Secret retrieval succeeded using workload identity
- No client secret/password stored in Kubernetes
- Secret value was not exposed during validation

## Final Result

Key Vault secret retrieval: SUCCESS
Authentication: Workload Identity
Authorization: Key Vault Secrets User
Secret value: NOT DISPLAYED
