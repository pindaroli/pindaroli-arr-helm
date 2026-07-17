# GEMINI.md

This file provides context and guidance for Gemini when working with this Helm charts repository.

## Repository Overview

This repository contains Helm charts for Kubernetes applications maintained by Pindaroli/Pindaroli. The primary focus is on the **Servarr stack** (Sonarr, Radarr, Lidarr, etc.) and related media services.

**Key Files:**
- `charts/servarr`: The main chart for the media stack.
- `k8s-lab/servarr/arr-values.yaml`: The real values file used for deployment in the homelab.
- `TESTING.md`: detailed testing strategies.
- `instructions/`: Directory containing specific task instructions and prompts.
    - `instructions/LIBRARY_CHART_TODO.md`: Plan for creating the common library chart.
    - `instructions/RESUME_PROMPT.md`: Prompt to resume the library chart work.

## Architecture & patterns

- **Chart Structure**: Standard Helm layout (`Chart.yaml`, `values.yaml`, `templates/`).
- **Servarr Pattern**: The `servarr` chart is a "umbrella" or multi-service chart where each sub-application (e.g., `sonarr`, `radarr`) has its own subdirectory in `templates/` and configuration block in `values.yaml`.
- **Shared Resources**:
    - **Media Volume**: `jellyfin` acts as the master for the media volume (`share-media` logic often implied or explicit in persistence config), with other apps mounting subpaths (e.g., `tv`, `movies`).
    - **Ingress**: Uses `nginx` ingress controller with simple host-based routing (e.g., `radarr.local`).

## Key Commands

### Helm Operations

```bash
# Lint the servarr chart
helm lint charts/servarr

# Dry-run install con il file dei valori specifici
helm install servarr charts/servarr -f ../k8s-lab/servarr/arr-values.yaml --dry-run --debug

# Install/Upgrade della release
helm upgrade --install servarr charts/servarr -f ../k8s-lab/servarr/arr-values.yaml

# Uninstall
helm uninstall servarr
```

### Verification

```bash
# Controlla tutti i pod nella release
kubectl get pods -l app.kubernetes.io/instance=servarr

# Controlla lo stato dell'ingress
kubectl get ingress -l app.kubernetes.io/instance=servarr
```

## Service Directory

Based on the default configuration, the following services are configured:

| Service | Internal Port | External Host | Description |
| :--- | :--- | :--- | :--- |
| **Jellyfin** | 8096 | `jellyfin.local` | Media Server (Volume Master) |
| **Sonarr** | 80 | `sonarr.local` | TV Shows |
| **Radarr** | 7878 | `radarr.local` | Movies |
| **Lidarr** | 8686 | `lidarr.local` | Music |
| **Readarr** | 8787 | `readarr.local` | Books |
| **Bazarr** | 6767 | `bazarr.local` | Subtitles |
| **qBittorrent** | 8080 (Web) | `qbittorrent.local` | Downloader |
| **Prowlarr** | 9696 | `prowlarr.local` | Indexer Manager |
| **Jellyseerr** | 5055 | `jellyseerr.local` | Request Management |
| **FlareSolverr** | 8191 | N/A | Cloudflare Solver (Internal) |

## Configuration Notes

- **Persistence**: Most apps are configured to use a shared persistence model where `jellyfin` claims the volume, or they share a PVC. Ensure the underlying storage class supports `ReadWriteMany` if running on multiple nodes, or rely on node affinity.
- **Ingress**: All external access is configured via `nginx` ingress. TLS is currently commented out or handled globally/separately in some configs (check `ingress` sections in values).

## Development Workflow

1.  **Modify Charts**: Edit files in `charts/servarr/templates/`.
2.  **Bump Version**: Increment `version` in `Chart.yaml` following SemVer rules (z for minor/patch fixes, y for new features/components).
3.  **Update Values**: Reflect changes in `k8s-lab/servarr/arr-values.yaml` if they are configuration overrides.
4.  **Test**: Use `helm template` to verify YAML validity and `helm lint charts/servarr`.
5.  **Deploy**: Commit, push to trigger release pipeline, and apply changes to the cluster using `-n arr`.

## Chart Versioning & Namespace Rules (Mandatory)
- **Semantic Versioning**: Ogni volta che si apportano modifiche ai chart Helm (`Chart.yaml`), è **obbligatorio** incrementare la versione del chart (`version: x.y.z`):
  - **Modifiche di lieve entità / Bugfix**: Incrementare la versione patch `z` (es. `1.5.9` → `1.5.10`).
  - **Modifiche sostanziose / Nuove funzionalità / Nuovi componenti**: Incrementare la versione minor `y` (es. `1.5.9` → `1.6.0`).
- **Namespace Enforcing**: Tutti i comandi di `helm` (`upgrade`, `install`, `list`, `rollback`) per lo stack Servarr DEVONO tassativamente includere la flag del namespace `-n arr` (es. `helm upgrade --install servarr charts/servarr -f ../k8s-lab/servarr/arr-values.yaml -n arr`).

