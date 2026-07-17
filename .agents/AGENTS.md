## Security & Secrets Management
All sensitive variables, credentials, and passwords in the workspace MUST be managed securely using SOPS.
- **Rule**: Never hardcode secrets in plain text inside Helm `values.yaml` files (e.g., `arr-values.yaml`).
- **Action**: Place any new secret in an encrypted file matching the pattern `secrets-sops/*.enc.yaml` or `helm-charts/*/secrets.enc.yaml`.
- **Integration**: Use `envFrom` or `secretKeyRef` in Kubernetes manifests to load the encrypted secrets into the application environment. If a Helm chart does not support these, modify the chart's templates to support them before proceeding.

## Chart Versioning & Namespace Rules (Mandatory)
- **Semantic Versioning**: Ogni volta che si apportano modifiche ai chart Helm (`Chart.yaml`), è **obbligatorio** incrementare la versione del chart (`version: x.y.z`):
  - **Modifiche di lieve entità / Bugfix**: Incrementare la versione patch `z` (es. `1.5.9` → `1.5.10`).
  - **Modifiche sostanziose / Nuove funzionalità / Nuovi componenti**: Incrementare la versione minor `y` (es. `1.5.9` → `1.6.0`).
- **Namespace Enforcing**: Tutti i comandi di `helm` (`upgrade`, `install`, `list`, `rollback`) per lo stack Servarr DEVONO tassativamente includere la flag del namespace `-n arr` (es. `helm upgrade --install servarr charts/servarr -f ../k8s-lab/servarr/arr-values.yaml -n arr`).

