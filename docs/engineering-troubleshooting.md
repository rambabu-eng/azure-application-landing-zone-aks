# AKS Application Landing Zone — Engineering Troubleshooting & Learnings

This document captures selected engineering problems encountered while designing, deploying, securing, operating, and tearing down the Azure AKS Application Landing Zone.

The focus is not on recording every command or error message. Each scenario captures the engineering reasoning used to move from symptom to diagnosis, root cause, remediation, and verification.

## Troubleshooting Method

For each issue:

**Area → Symptom → Investigation → Root Cause → Resolution → Verification → Engineering Lesson**

---

## 1. Terraform Saved Plan Became Stale

**Area:** Infrastructure as Code / Terraform / Deployment Safety

**Symptom**

A Terraform Apply failed after an earlier apply attempt had already made partial infrastructure changes. Re-running the previously generated saved plan returned a `Saved plan is stale` error.

**Investigation**

The earlier deployment had changed the remote Terraform state before failing on another Azure dependency. The saved plan therefore represented an older version of the infrastructure state.

**Root Cause**

Terraform saved plans are tied to the state snapshot from which they were generated. Once infrastructure or Terraform state changes, the previous plan can no longer safely represent the intended deployment.

**Resolution**

A completely new pipeline run was started to:

1. Refresh the remote state.
2. Generate a new Terraform plan.
3. Review the updated changes.
4. Apply the new saved plan through the controlled approval stage.

**Verification**

The fresh plan applied successfully and subsequent Terraform planning showed no infrastructure drift.

**Engineering Lesson**

Do not repeatedly retry an old Terraform plan after partial infrastructure changes. Regenerate the plan from current state before continuing.

**Operational Principle:** State consistency and safe recovery are more important than forcing a failed deployment to continue.

---

## 2. Azure Resource Provider Registration Blocked Deployment

**Area:** Azure Platform / Subscription Readiness

**Symptom**

Terraform failed while enabling AKS observability with:

`MissingSubscriptionRegistration`

for `Microsoft.Monitor`.

**Investigation**

The Terraform configuration itself was valid. The failure occurred when Azure attempted to provision monitoring resources whose resource provider was not registered in the application subscription.

Provider registration was checked for:

- Microsoft.Monitor
- Microsoft.OperationalInsights
- Microsoft.Insights

**Root Cause**

The application subscription had not previously used the required Azure Monitor resource types, so the necessary resource provider was not registered.

**Resolution**

The missing provider was registered and its status was confirmed before generating a new Terraform plan.

**Verification**

The observability deployment subsequently created the Azure Monitor Workspace, DCR/DCE resources, Container Insights integration, and managed Prometheus configuration successfully.

**Engineering Lesson**

Infrastructure failures are not always caused by Terraform code. Subscription prerequisites, provider registrations, quotas, policies, and permissions should be checked as part of platform-level diagnosis.

---

## 3. Kubernetes Desired State Did Not Match Runtime State

**Area:** Kubernetes / CI/CD / Deployment Verification

**Symptom**

The Azure DevOps pipeline reported success, but live AKS workloads did not contain the newly configured CPU/memory requests, limits, or Pod Disruption Budget.

**Investigation**

The live Deployment was queried and returned empty resource configuration. The PDB was also not found.

The pipeline was reviewed and found to be performing only:

`kubectl set image`

rather than reapplying the Kubernetes manifests.

**Root Cause**

Updating only the container image changed the image tag but did not apply changes made elsewhere in `deployment.yaml` or the new `pdb.yaml`.

**Resolution**

The deployment pipeline was changed to:

1. Apply the Kubernetes Deployment manifest.
2. Apply the Pod Disruption Budget manifest.
3. Set the immutable Build ID image.
4. Wait for rollout completion.
5. Query the resulting workload state.

**Verification**

The live cluster returned:

- CPU request: `100m`
- Memory request: `128Mi`
- CPU limit: `500m`
- Memory limit: `256Mi`
- PDB present with `minAvailable: 1`

**Engineering Lesson**

A green CI/CD pipeline proves that the pipeline completed — not necessarily that runtime state matches intended configuration.

Always verify the deployed state.

---

## 4. Trivy Blocked Container Promotion

**Area:** Container Security / DevSecOps

**Symptom**

Trivy blocked the container pipeline because HIGH-severity vulnerabilities were detected in:

- msgpack
- setuptools
- urllib3

**Investigation**

Application package versions were upgraded, but the same vulnerabilities remained.

Further inspection showed that vulnerable versions were vendored inside the runtime installation of `pip`, rather than directly used by the application.

**Root Cause**

The vulnerable packages existed as tooling dependencies inside the production container image.

**Resolution**

The Dockerfile was hardened so that after application dependencies were installed, unnecessary package-management tooling was removed from the final runtime image:

`pip` and `setuptools` were uninstalled.

**Verification**

The image was rebuilt and Trivy completed successfully with no blocking HIGH findings.

**Engineering Lesson**

Container vulnerability findings should be investigated to determine whether they come from:

- application dependencies,
- operating system packages,
- build tooling,
- vendored libraries,
- or the runtime base image.

The correct response is to reduce unnecessary runtime attack surface rather than blindly upgrading packages.

---

## 5. Checkov Findings Required Engineering Classification

**Area:** Infrastructure Security / Governance

**Symptom**

Initial Checkov scans produced multiple failed controls across Terraform and Azure Verified Modules.

**Investigation**

Each failure was reviewed instead of disabling the scanner globally.

Findings included:

- Terraform module source pinning expectations
- ACR private endpoint requirements
- geo-replication / availability expectations
- Key Vault network controls
- container registry security controls

**Root Cause**

Some controls represented genuine security expectations, while others did not align with the project's lab scope, selected Azure SKU, or Microsoft AVM delivery model.

For example, ACR Basic does not support all Premium networking features.

**Resolution**

Applicable controls were implemented. Remaining intentional deviations were documented with architectural justification and compensating controls.

Checkov remained a **blocking pipeline gate**.

**Verification**

Final security scanning completed with:

`Passed checks: 60`
`Failed checks: 0`

after documented exceptions were applied.

**Engineering Lesson**

Security scanning should not become either:

- “fix every warning blindly”, or
- “soft-fail everything”.

Engineering judgement means understanding the control, the risk, the architecture, and the compensating control.

---

## 6. Key Vault Secret Creation Was Denied by Governance

**Area:** Azure Policy / Key Vault / Governance

**Symptom**

Workload Identity authentication succeeded, but creating a Key Vault secret through the REST API returned `403 Forbidden`.

**Investigation**

Identity authentication and Key Vault connectivity were checked first.

The workload could reach the private Key Vault endpoint and authenticate successfully, indicating that networking and Workload Identity were functioning.

Azure Policy assignments were then reviewed.

**Root Cause**

A governance initiative enforced a maximum secret validity period. The attempted secret did not contain a compliant expiry value.

**Resolution**

The secret was recreated with an expiry within the permitted policy window.

**Verification**

The compliant secret operation succeeded and the AKS workload was able to access Key Vault through its managed identity.

**Engineering Lesson**

A `403` does not automatically mean “RBAC problem”.

Authorization failures can originate from:

- identity,
- RBAC,
- Azure Policy,
- network restrictions,
- resource configuration,
- or application-level permissions.

Diagnosis should isolate these layers rather than immediately adding broader permissions.

---

## 7. Workload Identity Required End-to-End Verification

**Area:** Identity / Kubernetes / Key Vault

**Symptom**

AKS Workload Identity components appeared correctly configured, but configuration alone did not prove that a pod could authenticate to Azure.

**Investigation**

The complete identity chain was validated:

`Pod → Service Account → Federated Credential → UAMI → Microsoft Entra ID → Key Vault`

Environment variables and the federated token file were verified inside the pod.

A token exchange was then executed from the workload.

**Root Cause**

There was no configuration failure — the engineering requirement was proving that all identity components worked together at runtime.

**Resolution**

An in-pod authentication test was performed using Azure Identity and a Key Vault client.

**Verification**

The workload successfully exchanged its Kubernetes federated token for an Azure token and accessed the private Key Vault endpoint.

**Engineering Lesson**

Identity architecture should be verified at the consuming workload, not only by checking that cloud resources exist.

---

## 8. Private AKS Changed the Troubleshooting Approach

**Area:** Networking / Kubernetes Operations

**Symptom**

Normal local `kubectl` access was unavailable because the AKS API endpoint was private.

**Investigation**

Cluster health was confirmed through Azure while recognizing that the local workstation did not have direct network reachability to the private API endpoint.

**Root Cause**

The behavior was expected from the security architecture: the AKS control plane was intentionally private.

**Resolution**

Azure-managed command execution was used:

`az aks command invoke`

This allowed controlled execution of Kubernetes commands without exposing the AKS API publicly.

**Verification**

Pods, Workload Identity configuration, Kubernetes resources, and rollout state were successfully inspected through the private cluster.

**Engineering Lesson**

Security architecture changes operational procedures.

A private service may require:

- jump hosts,
- private runners,
- VPN/ExpressRoute,
- Bastion-style administration,
- or provider-managed command execution.

Do not weaken network security simply to make administration easier.

---

## 9. Observability Was Verified With Real Telemetry

**Area:** Monitoring / Observability / Operations

**Symptom**

Azure Monitor, Container Insights, and Managed Prometheus resources deployed successfully, but deployment success alone did not prove telemetry collection.

**Investigation**

Log Analytics was queried for actual cluster and workload records.

Queries included:

- `KubePodInventory`
- `ContainerLogV2`

**Root Cause**

There was no infrastructure failure; this was an operational validation requirement.

**Resolution**

Real workload logs and Kubernetes inventory records were queried and reviewed.

**Verification**

Telemetry included:

- AKS system workloads
- application pods
- Gunicorn startup logs
- application container output

Managed Prometheus resources and alert rules were also verified.

**Engineering Lesson**

Observability is complete only when the telemetry path works:

`Workload → Collector → Monitoring Platform → Query / Alert`

Provisioning a monitoring resource is not the same as proving observability.

---

## 10. Terraform Destroy Partially Failed Due to DNS Resolution

**Area:** Networking / Operations / Infrastructure Lifecycle

**Symptom**

Terraform destroy successfully removed most of the application landing zone but failed while deleting the private endpoint subnet with:

`dial tcp: lookup management.azure.com: no such host`

**Investigation**

The failure occurred while Terraform was polling Azure Resource Manager, not because Azure rejected the resource deletion.

DNS and TCP connectivity were checked using:

`Resolve-DnsName management.azure.com`

and:

`Test-NetConnection management.azure.com -Port 443`

**Root Cause**

A temporary DNS resolution failure on the local workstation interrupted communication with Azure Resource Manager.

**Resolution**

After DNS and HTTPS connectivity recovered, the previous saved destroy plan was not reused.

A new Terraform destroy plan was generated from the updated state.

**Verification**

The fresh plan identified only eight remaining resources.

The second apply completed:

`0 added, 0 changed, 8 destroyed`

Final verification showed:

- empty Terraform state
- `ResourceGroupNotFound` for the application resource group

**Engineering Lesson**

A partial infrastructure failure does not mean starting again or manually deleting everything.

First determine:

1. what actually succeeded,
2. what remains in state,
3. whether the failure is Azure, network, permissions, or Terraform,
4. then generate a new plan from current reality.

---

# Cross-Layer Troubleshooting Model

The project reinforced a useful troubleshooting order:

1. **Application** — Is the workload behaving correctly?
2. **Kubernetes** — Pods, probes, resources, services, deployments, PDB.
3. **Identity** — Service Account, federation, managed identity, RBAC.
4. **Network** — DNS, routing, private endpoints, NSGs, peering.
5. **Azure Resource** — Service configuration and provisioning state.
6. **Governance** — Azure Policy and organizational controls.
7. **Subscription / Platform** — Provider registration, quota, shared services.
8. **IaC / State** — Terraform configuration, state, plan, drift.
9. **Pipeline** — Branch conditions, approvals, artifacts, security gates.
10. **Observability** — Logs, metrics, alerts, and runtime evidence.

A useful principle throughout the project was:

> Do not immediately change the component reporting the error. First determine which layer actually owns the failure.

---

# Engineering Takeaways

This project reinforced that production-oriented cloud engineering is less about remembering Azure commands and more about understanding dependencies and failure domains.

The most important practices demonstrated were:

- verify runtime state rather than trusting deployment success alone;
- isolate identity, networking, governance, and application failures before changing permissions;
- regenerate Terraform plans after state changes;
- treat security gates as engineering controls rather than checkbox tools;
- validate monitoring using actual telemetry;
- use least privilege instead of solving failures through broader access;
- preserve evidence before teardown;
- use controlled teardown and cost management as part of the infrastructure lifecycle.