# Library Chart Refactoring Plan — ✅ COMPLETED 2026-05-17

We planned to create a Helm library chart to share common templates across the `servarr` stack.

## Goal
Create `charts/pindaroli-common` (Library Chart) and refactor `charts/servarr` to use it.

## Execution Summary
- **Created Library Chart**: Designed and implemented `charts/pindaroli-common` (`type: library`, v1.0.0).
- **Generic Templates**: Developed modular templates for `deployment`, `service`, `ingress`, `hpa`, `pvc`, and `serviceaccount` to dynamically parse and apply configurations based on standard schema keys.
- **Refactored Servarr**: Migrated **all 8 standard workloads** (`sonarr`, `radarr`, `lidarr`, `readarr`, `bazarr`, `prowlarr`, `jellyseerr`, and `flaresolverr`).
- **Impact**: Deleted over **2,000 lines of duplicate Helm templates**, reducing maintenance overhead.
- **CI/CD Integration**: Merged into `main` and pushed to remote to trigger the automatic package and release of `servarr` v1.2.6 on GitHub Pages.

