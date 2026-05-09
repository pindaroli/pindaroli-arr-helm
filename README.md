# 🚀 Pindaroli ARR Helm Charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/pindaroli&style=for-the-badge)](https://artifacthub.io/packages/search?repo=pindaroli)

Benvenuti nel mio repository personale di **Helm Charts**. Questo progetto raccoglie distribuzioni ottimizzate per Kubernetes, con un focus particolare sullo stack **Servarr** (Sonarr, Radarr, Lidarr, ecc.) e soluzioni di networking avanzate.

Il repository è configurato con una pipeline **CI/CD** automatizzata che pubblica le chart tramite **GitHub Pages**.

## 🛠 Charts Incluse

| Chart | Descrizione |
| :--- | :--- |
| **servarr** | Stack completo per media management (Sonarr, Radarr, etc.) |
| **cloudflared** | Tunnel Cloudflare per accesso sicuro |
| **outline** | Wiki/Knowledge base aziendale |
| **penpot** | Alternativa open-source a Figma |
| **traefik-whitelist-ddns** | Gestione whitelist IP dinamici per Traefik |

## 🚀 Utilizzo Rapido

Aggiungi il repository a Helm:

```bash
helm repo add pindaroli https://pindaroli.github.io/pindaroli-arr-helm//
helm repo update
```

Cerca una chart:

```bash
helm search repo pindaroli
```

## 📦 Installazione Esempio

```bash
helm install mio-stack pindaroli/servarr -f mio-values.yaml
```

## 📄 Licenza

Distribuito sotto licenza Apache 2.0. Copyright &copy; 2024 Pindaroli.
