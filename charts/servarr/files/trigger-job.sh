#!/usr/bin/env bash
set -euo pipefail

CONTENT_PATH="${1:-}"
CATEGORY="${2:-video-filebot}"
TRUENAS_IP="${TRUENAS_IP:-10.10.10.50}"
NORMALIZER_PORT="${NORMALIZER_PORT:-9000}"

if [ -z "$CONTENT_PATH" ]; then
    echo "⚠️ Errore: Nessun CONTENT_PATH fornito a trigger-job.sh"
    exit 1
fi

echo "🚀 Innesco Webhook Normalizer TrueNAS: $CONTENT_PATH (Categoria: $CATEGORY)"

curl -s -f -X POST "http://${TRUENAS_IP}:${NORMALIZER_PORT}/hooks/normalize" \
    --data-urlencode "path=${CONTENT_PATH}" \
    --data-urlencode "category=${CATEGORY}"

echo "✅ Richiesta di normalizzazione accettata da TrueNAS."
