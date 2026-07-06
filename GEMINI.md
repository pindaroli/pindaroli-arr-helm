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

# Dry-run install with the specific values file
helm install oli-arr charts/servarr -f ../k8s-lab/servarr/arr-values.yaml --dry-run --debug

# Install/Upgrade the release
helm upgrade --install oli-arr charts/servarr -f ../k8s-lab/servarr/arr-values.yaml

# Uninstall
helm uninstall oli-arr
```

### Verification

```bash
# Check all pods in the release
kubectl get pods -l app.kubernetes.io/instance=oli-arr

# Check ingress status
kubectl get ingress -l app.kubernetes.io/instance=oli-arr
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
2.  **Update Values**: Reflect changes in `k8s-lab/servarr/arr-values.yaml` if they are configuration overrides.
3.  **Test**: Use `helm template` to verify YAML validity.
4.  **Deploy**: Apply changes to the cluster.
