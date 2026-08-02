#!/usr/bin/env bash
set -euo pipefail

CONTENT_PATH="${1:-}"
CATEGORY="${2:-}"

if [ -z "$CONTENT_PATH" ]; then
    echo "⚠️ Errore: Nessun CONTENT_PATH fornito a trigger-job.sh"
    exit 1
fi

echo "🚀 Innesco Job K8s per: $CONTENT_PATH (Categoria: $CATEGORY)"

TARGET_OUTPUT=""
FILTER_TYPE="audio"

{{- if .Values.qbittorrent.triggerJob.filters }}
case "$CATEGORY" in
  {{- range $cat, $dest := .Values.qbittorrent.triggerJob.filters }}
  "{{ $cat }}")
    TARGET_OUTPUT=$(echo "{{ $dest }}" | awk '{print $1}')
    FILTER_TYPE=$(echo "{{ $dest }}" | awk '{print $2}')
    if [ -z "$FILTER_TYPE" ]; then
        FILTER_TYPE="audio"
    fi
    echo "ℹ️ Applicato filtro categoria '$CATEGORY'. Destinazione: $TARGET_OUTPUT (Tipo: $FILTER_TYPE)"
    ;;
  {{- end }}
  *)
    echo "ℹ️ Categoria '$CATEGORY' non presente nei filtri. Esco senza lanciare il Job."
    exit 0
    ;;
esac
{{- else }}
echo "ℹ️ Nessun filtro configurato per le categorie. Esco senza lanciare il Job."
exit 0
{{- end }}

K8S_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
K8S_CA="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
K8S_API="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null || echo "{{ .Release.Namespace }}")"

SONGKONG_VERBOSE="${SONGKONG_VERBOSE:-{{ .Values.qbittorrent.triggerJob.verbose | default false }}}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-{{ .Values.qbittorrent.triggerJob.recipient | default "" }}}"

JSON_PAYLOAD=$(jq -n \
  --arg path "$CONTENT_PATH" \
  --arg target_output "$TARGET_OUTPUT" \
  --arg filter_type "$FILTER_TYPE" \
  --arg songkong_verbose "$SONGKONG_VERBOSE" \
  --arg email_recipient "$EMAIL_RECIPIENT" \
  --arg ns "$NAMESPACE" \
  '{
    "apiVersion": "batch/v1",
    "kind": "Job",
    "metadata": {
      "generateName": "\($filter_type)-normalizer-",
      "namespace": $ns
    },
    "spec": {
      "ttlSecondsAfterFinished": 600,
      "backoffLimit": 0,
      "template": {
        "metadata": {
          "labels": {
            "app.kubernetes.io/name": "audio-normalizer"
          }
        },
        "spec": {
          "restartPolicy": "Never",
          "affinity": {
            "podAntiAffinity": {
              "requiredDuringSchedulingIgnoredDuringExecution": [
                {
                  "labelSelector": {
                    "matchExpressions": [
                      { "key": "app.kubernetes.io/name", "operator": "In", "values": ["qbittorrent"] }
                    ]
                  },
                  "topologyKey": "kubernetes.io/hostname"
                }
              ]
            }
          },
          "securityContext": {
            "runAsUser": 1000,
            "runAsGroup": 1000
          },
          "containers": [
            {
              "name": "normalizer",
              "image": "ghcr.io/pindaroli/custom-normalizer:1.2.5",
              "imagePullPolicy": "Always",
              "command": [
                "\(if $filter_type == "video" then "/app/normalize-video.sh" else "/app/normalize.sh" end)"
              ],
              "args": [$path, $target_output, "/media", $email_recipient],
              "resources": {
                "requests": {
                  "cpu": "200m",
                  "memory": "512Mi"
                },
                "limits": {
                  "cpu": "2",
                  "memory": "2Gi"
                }
              },
              "env": [
                {
                  "name": "LANG",
                  "value": "C.UTF-8"
                },
                {
                  "name": "LC_ALL",
                  "value": "C.UTF-8"
                },
                {
                  "name": "SONGKONG_VERBOSE",
                  "value": $songkong_verbose
                },
                {
                  "name": "EMAIL_RECIPIENT",
                  "value": $email_recipient
                },
                {
                  "name": "SMTP_HOST",
                  "valueFrom": { "secretKeyRef": { "name": "smtp-creds", "key": "smtp-host" } }
                },
                {
                  "name": "SMTP_PORT",
                  "valueFrom": { "secretKeyRef": { "name": "smtp-creds", "key": "smtp-port" } }
                },
                {
                  "name": "SMTP_USER",
                  "valueFrom": { "secretKeyRef": { "name": "smtp-creds", "key": "smtp-user" } }
                },
                {
                  "name": "SMTP_PASS",
                  "valueFrom": { "secretKeyRef": { "name": "smtp-creds", "key": "smtp-pass" } }
                },
                {
                  "name": "SMTP_FROM",
                  "valueFrom": { "secretKeyRef": { "name": "smtp-creds", "key": "smtp-from" } }
                },
                {
                  "name": "TELEGRAM_BOT_TOKEN",
                  "valueFrom": { "secretKeyRef": { "name": "servarr-api-keys", "key": "telegram-token" } }
                },
                {
                  "name": "TELEGRAM_CHAT_ID",
                  "valueFrom": { "secretKeyRef": { "name": "servarr-api-keys", "key": "telegram-chat-id" } }
                }
              ],
              "volumeMounts": [
                { "name": "media-data", "mountPath": "/media" },
                { "name": "songkong-license", "mountPath": "/root/.songkong/license.properties", "subPath": "license.properties" },
                { "name": "filebot-license", "mountPath": "/root/.filebot/license.psm", "subPath": "license.psm" }
              ]
            }
          ],
          "volumes": [
            {
              "name": "media-data",
              "persistentVolumeClaim": { "claimName": "{{ .Values.jellyfin.persistence.media.existingClaim | default (printf "%s-jellyfin-media" .Release.Name) }}" }
            },
            {
              "name": "songkong-license",
              "secret": { "secretName": "songkong-license" }
            },
            {
              "name": "filebot-license",
              "secret": { "secretName": "filebot-license", "optional": true }
            }
          ]
        }
      }
    }
  }'
)

HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --cacert "$K8S_CA" \
  -H "Authorization: Bearer $K8S_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST -d "$JSON_PAYLOAD" "${K8S_API}/apis/batch/v1/namespaces/${NAMESPACE}/jobs")

if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ Job creato con successo per: $CONTENT_PATH"
else
    echo "❌ Errore nella creazione del Job. Codice HTTP: $HTTP_CODE"
    exit 1
fi
