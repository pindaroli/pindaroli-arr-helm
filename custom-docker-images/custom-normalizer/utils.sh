#!/usr/bin/env bash
# File contenente funzioni di utilità condivise tra gli script di normalizzazione

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Invia un messaggio Telegram formattato
# Uso: send_telegram <messaggio_html> <titolo_apprise>
send_telegram() {
    local msg="$1"
    local title="$2"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        apprise -t "$title" -b "$msg" -i html "tgram://${TELEGRAM_BOT_TOKEN}/${TELEGRAM_CHAT_ID}/" >/dev/null 2>&1 || true
    fi
}

# Invia email riassuntiva tramite Apprise, con fallback su Telegram
# Uso: send_summary_email <destinatario> <titolo> <body> <messaggio_fallback_telegram> [allegato]
send_summary_email() {
    local recipient="$1"
    local title="$2"
    local body="$3"
    local fallback_text="$4"
    local attachment="${5:-}"

    if [ -n "$recipient" ]; then
        if [ -n "${SMTP_HOST:-}" ] && [ -n "${SMTP_USER:-}" ] && [ -n "${SMTP_PASS:-}" ]; then
            echo "📧 Invio email di riepilogo a $recipient..."
            
            local smtp_params="from=${SMTP_FROM:-$SMTP_USER}&to=${recipient}"
            if [ "${SMTP_PORT:-465}" = "465" ]; then
                smtp_params="${smtp_params}&mode=ssl"
            fi

            # Codifica URL della @ nel nome utente per evitare errori di parsing in Apprise
            local encoded_user="$(echo "$SMTP_USER" | sed 's/@/%40/g')"
            local apprise_smtp_url="mailtos://${encoded_user}:${SMTP_PASS}@${SMTP_HOST}:${SMTP_PORT:-465}?${smtp_params}"

            local apprise_cmd=(apprise -t "$title" -b "$body" "$apprise_smtp_url")
            if [ -n "$attachment" ]; then
                apprise_cmd+=("--attach" "$attachment")
            fi

            # Tenta l'invio dell'email via Apprise. Se fallisce, invia notifica Telegram via curl usando i segreti K8s
            if ! "${apprise_cmd[@]}"; then
                echo "⚠️ Warning: Invio email tramite Apprise fallito. Invio avviso di backup via Telegram..."
                if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d chat_id="${TELEGRAM_CHAT_ID}" \
                        -d parse_mode="HTML" \
                        -d text="${fallback_text}" || true
                else
                    echo "⚠️ Warning: Credenziali Telegram non disponibili per l'avviso di backup."
                fi
            fi
        else
            echo "⚠️ Errore: Destinatario email impostato ma credenziali SMTP non configurate."
        fi
    fi
}
