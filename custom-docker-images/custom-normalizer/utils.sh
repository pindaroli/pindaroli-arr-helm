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

# Costruisce un template HTML responsive per le notifiche email dei normalizzatori
# Uso: build_html_email_template <icona> <titolo_principale> <sottotitolo> <badge_status> <colore_badge> <dettagli_table_html> [sezione_extra_html]
build_html_email_template() {
    local icon="$1"
    local main_title="$2"
    local subtitle="$3"
    local badge_status="$4"
    local badge_color="${5:-#10b981}"  # default verde (#10b981)
    local table_rows="$6"
    local extra_section="${7:-}"

    cat <<EOF
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$main_title</title>
</head>
<body style="margin: 0; padding: 20px; background-color: #f1f5f9; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1e293b;">
  <div style="max-width: 620px; margin: 0 auto; background: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06); border: 1px solid #e2e8f0;">
    <!-- Header -->
    <div style="background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%); padding: 24px; color: #ffffff;">
      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="font-size: 26px; vertical-align: middle;">$icon</td>
          <td style="text-align: right; vertical-align: middle;">
            <span style="background-color: ${badge_color}; color: #ffffff; font-size: 11px; font-weight: 700; text-transform: uppercase; padding: 4px 10px; border-radius: 9999px; letter-spacing: 0.05em; display: inline-block;">$badge_status</span>
          </td>
        </tr>
      </table>
      <h2 style="margin: 12px 0 4px 0; font-size: 18px; font-weight: 700; color: #ffffff; line-height: 1.3;">$main_title</h2>
      <p style="margin: 0; font-size: 12px; color: #94a3b8;">$subtitle</p>
    </div>

    <!-- Body Content -->
    <div style="padding: 24px;">
      <h3 style="margin: 0 0 14px 0; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b; border-bottom: 2px solid #f1f5f9; padding-bottom: 6px;">Dettagli Elaborazione</h3>
      
      <table style="width: 100%; border-collapse: collapse; margin-bottom: 16px; font-size: 13px;">
        <tbody>
          $table_rows
        </tbody>
      </table>

      $extra_section
    </div>

    <!-- Footer -->
    <div style="background-color: #f8fafc; padding: 14px 24px; font-size: 11px; color: #94a3b8; border-top: 1px solid #e2e8f0; text-align: center;">
      Servizio di Notifica Automatico Homelab · Normalizer
    </div>
  </div>
</body>
</html>
EOF
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

            local apprise_cmd=(apprise -i html -t "$title" -b "$body" "$apprise_smtp_url")
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
