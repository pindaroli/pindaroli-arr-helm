## Security & Secrets Management
All sensitive variables, credentials, and passwords in the workspace MUST be managed securely using SOPS.
- **Rule**: Never hardcode secrets in plain text inside Helm `values.yaml` files (e.g., `arr-values.yaml`).
- **Action**: Place any new secret in an encrypted file matching the pattern `secrets-sops/*.enc.yaml` or `helm-charts/*/secrets.enc.yaml`.
- **Integration**: Use `envFrom` or `secretKeyRef` in Kubernetes manifests to load the encrypted secrets into the application environment. If a Helm chart does not support these, modify the chart's templates to support them before proceeding.
