#!/usr/bin/env bash
set -euo pipefail

# Script di normalizzazione Video tramite FileBot con notifiche Telegram
# USO: normalize-video.sh <SOURCE_PATH> [OUTPUT_DIR] [MEDIA_BASE]
#
# Esempio:
#   normalize-video.sh radarr/Movies /media/movies /media

export HOME="${HOME:-/tmp}"
[ "$HOME" = "/" ] && export HOME=/tmp
export JAVA_OPTS="${JAVA_OPTS:-} -Duser.home=/tmp"

MEDIA_BASE="${3:-/media/downloads}"
EMAIL_RECIPIENT="${4:-}"

RAW_SOURCE="${1:-}"
RAW_TARGET="${2:-}"

source "$(dirname "$0")/utils.sh"

if [ -z "$RAW_SOURCE" ]; then
    echo "❌ Errore: Sorgente non specificata."
    exit 1
fi

# Risoluzione percorso sorgente (assoluto o relativo a /media/downloads)
if [[ "$RAW_SOURCE" == /* ]]; then
    SOURCE_DIR="$RAW_SOURCE"
else
    SOURCE_DIR="${MEDIA_BASE}/${RAW_SOURCE}"
fi

# Rimozione eventuale slash finale
SOURCE_DIR="${SOURCE_DIR%/}"
BASENAME="$(basename "$SOURCE_DIR")"

# Risoluzione percorso destinazione
if [ -n "$RAW_TARGET" ]; then
    if [[ "$RAW_TARGET" == /* ]]; then
        TARGET_DIR="$RAW_TARGET"
    else
        TARGET_DIR="${MEDIA_BASE}/${RAW_TARGET}"
    fi
    TARGET_DIR="${TARGET_DIR%/}"
else
    TARGET_DIR="${SOURCE_DIR} - normalize"
fi

echo "=========================================================="
echo "  🎬 INIZIO PROCESSO DI NORMALIZZAZIONE VIDEO (FILEBOT)"
echo "=========================================================="
echo "Sorgente : '$SOURCE_DIR'"
echo "Target   : '$TARGET_DIR'"
echo "=========================================================="

if [ ! -e "$SOURCE_DIR" ]; then
    ERR_MSG="❌ <b>[Normalizzazione Video] Errore Sorgente</b>
La directory/file sorgente <code>$SOURCE_DIR</code> non esiste!"
    echo "$ERR_MSG"
    send_telegram "$ERR_MSG" "🎬 [Video Normalizzatore]"
    exit 1
elif [ ! -r "$SOURCE_DIR" ]; then
    ERR_MSG="❌ <b>[Normalizzazione Video] Errore Permessi</b>
Permessi insufficienti per accedere a <code>$SOURCE_DIR</code>!"
    echo "$ERR_MSG"
    send_telegram "$ERR_MSG" "🎬 [Video Normalizzatore]"
    exit 1
fi

if [ -f "/etc/filebot/license.psm" ]; then
    echo "🔑 Attivazione licenza FileBot da /etc/filebot/license.psm..."
    filebot --license /etc/filebot/license.psm || true
elif [ -f "/root/.filebot/license.psm" ]; then
    echo "🔑 Attivazione licenza FileBot da /root/.filebot/license.psm..."
    filebot --license /root/.filebot/license.psm || true
else
    echo "⚠️  Attenzione: Nessuna licenza FileBot trovata in /etc/filebot/license.psm o /root/.filebot/license.psm. Alcune funzionalità di rename potrebbero fallire."
fi

mkdir -p "$TARGET_DIR"

PROCESSED_ITEMS=0
ERRORS=0

FILEBOT_LOG="/tmp/filebot_${BASENAME}.log"
rm -f "$FILEBOT_LOG"

process_filebot() {
    local src="$1"
    echo "----------------------------------------------------------"
    echo "📽️  Elaborazione: '$src'"
    
    if filebot -script fn:amc "$src" \
        --output "$TARGET_DIR" \
        --action hardlink \
        --conflict override \
        -non-strict \
        --lang it \
        --def movieDB=TheMovieDB \
        --def "movieFormat={n} ({y}) {'{tmdb-' + id + '}'}/{n} ({y}) {'{tmdb-' + id + '}'}{ ' [' + edition + ']' } - [{ any{source + ' '}{''} }{vf} {vc}]{ ' [' + group + ']' }" \
        --def artwork=y 2>&1 | tee -a "$FILEBOT_LOG"; then
        echo "✅ Elaborazione completata per '$(basename "$src")'."
        PROCESSED_ITEMS=$((PROCESSED_ITEMS + 1))
        # Pulizia post-processo: elimina eventuali file .nfo generati
        find "$TARGET_DIR" -maxdepth 2 -type f -name "*.nfo" -delete

        # Sanificazione automatica release preesistenti e pulizia artwork ridondanti
        local sanitize_script="$(dirname "$0")/sanitize_movie_folder.py"
        [ ! -f "$sanitize_script" ] && sanitize_script="/app/sanitize_movie_folder.py"

        if [ -f "$sanitize_script" ]; then
            echo "🧹 Ricerca cartelle film per sanificazione versioni multiple e artwork..."
            local dest_dirs
            dest_dirs=$(grep -E "^\[(HARDLINK|MOVE|COPY)\] from" "$FILEBOT_LOG" 2>/dev/null | awk -F 'to \\[' '{print $2}' | sed 's/\]$//' | while read -r f; do dirname "$f"; done | sort -u || true)
            for mdir in $dest_dirs; do
                if [ -d "$mdir" ]; then
                    echo "🧹 Esecuzione sanificazione automatica su: '$mdir'..."
                    MEDIA_DIR="$TARGET_DIR" python3 "$sanitize_script" "$mdir" --apply --no-refresh || true
                fi
            done
        fi
    else
        echo "❌ ERRORE durante l'elaborazione FileBot per '$(basename "$src")'."
        ERRORS=$((ERRORS + 1))
        send_telegram "❌ <b>[Normalizzazione Video] Errore FileBot</b>
<b>Sorgente:</b> <code>$src</code>
Si è verificato un errore durante l'esecuzione di FileBot." "🎬 [Video Normalizzatore]"
    fi
}

echo "🔧 Analisi della struttura sorgente..."
if [ -d "$SOURCE_DIR" ]; then
    # Verifica se la cartella sorgente contiene direttamente dei file video
    HAS_DIRECT_VIDEO=$(find "$SOURCE_DIR" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" -o -iname "*.iso" \) | head -n 1)

    if [ -n "$HAS_DIRECT_VIDEO" ]; then
        echo "📄 La cartella sorgente contiene direttamente file video. Elaborazione come singola entità."
        process_filebot "$SOURCE_DIR"
    else
        # Se non ha file video diretti, cerca sottocartelle di primo livello che non siano nascoste o di sistema (.trickplay, ecc.)
        SUBDIRS_COUNT=$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" ! -iname "*trickplay*" | wc -l)
        
        if [ "$SUBDIRS_COUNT" -gt 0 ]; then
            echo "📁 Trovate $SUBDIRS_COUNT sottocartelle valide di primo livello. Elaborazione in corso..."
            while IFS= read -r -d '' dir; do
                process_filebot "$dir"
            done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" ! -iname "*trickplay*" -print0)
        else
            echo "📄 Nessuna sottocartella valida trovata. Tentativo di elaborazione della cartella principale."
            process_filebot "$SOURCE_DIR"
        fi
    fi
else
    echo "📄 Il percorso sorgente è un file. Elaborazione file singolo..."
    process_filebot "$SOURCE_DIR"
fi

END_MSG="🎉 <b>[Normalizzazione Video] Elaborazione Completata</b>
<b>Sorgente:</b> <code>$SOURCE_DIR</code>
<b>Target:</b> <code>$TARGET_DIR</code>
<b>Elementi elaborati:</b> <code>$PROCESSED_ITEMS</code>
<b>Errori riscontrati:</b> <code>$ERRORS</code>"

echo ""
echo "=========================================================="
echo "🎉 ELABORAZIONE COMPLETATA!"
echo "Elementi elaborati : $PROCESSED_ITEMS"
echo "Errori riscontrati : $ERRORS"
echo "Directory finale   : '$TARGET_DIR'"
echo "=========================================================="

send_telegram "$END_MSG" "🎬 [Video Normalizzatore]"

# Innesco automatico dello scan della libreria Movies su Jellyfin
JELLYFIN_URL="${JELLYFIN_URL:-http://jellyfin:8096}"
JELLYFIN_TOKEN="${JELLYFIN_TOKEN:-7c80240c7a9b4326a8690ce140265a14}"
JELLYFIN_MOVIES_FOLDER_ID="${JELLYFIN_MOVIES_FOLDER_ID:-f137a2dd21bbc1b99aa5c0f6bf02a805}"

echo "📡 Innesco scan libreria Movies su Jellyfin (${JELLYFIN_URL})..."
if curl -s -f -X POST "${JELLYFIN_URL}/Items/${JELLYFIN_MOVIES_FOLDER_ID}/Refresh" \
    -H "Authorization: MediaBrowser Client=\"FileBot\", Device=\"Server\", DeviceId=\"filebot-normalizer\", Version=\"1.0.0\", Token=\"${JELLYFIN_TOKEN}\"" \
    -H "Content-Length: 0" >/dev/null 2>&1 || \
   curl -s -f -X POST "${JELLYFIN_URL}/Library/Refresh" \
    -H "Authorization: MediaBrowser Client=\"FileBot\", Device=\"Server\", DeviceId=\"filebot-normalizer\", Version=\"1.0.0\", Token=\"${JELLYFIN_TOKEN}\"" \
    -H "Content-Length: 0" >/dev/null 2>&1; then
    echo "✅ Scan libreria Jellyfin avviato con successo."
else
    echo "⚠️ Impossibile contattare Jellyfin per il refresh della libreria."
fi

if [ -n "$EMAIL_RECIPIENT" ]; then
    # Estrazione percorsi hardlink e dettagli film dal log di FileBot
    FINAL_DEST_FILES=$(grep -E "^\[HARDLINK\] from" "$FILEBOT_LOG" 2>/dev/null | awk -F 'to \\[' '{print $2}' | sed 's/\]$//' || true)
    FIRST_DEST=$(echo "$FINAL_DEST_FILES" | head -n 1)
    MOVIE_TITLE=""
    TMDB_ID=""
    TMDB_URL=""
    if [ -n "$FIRST_DEST" ]; then
        MOVIE_FOLDER=$(basename "$(dirname "$FIRST_DEST")")
        MOVIE_TITLE="$MOVIE_FOLDER"
        TMDB_ID=$(echo "$MOVIE_FOLDER" | grep -oE "tmdb-[0-9]+" | awk -F '-' '{print $2}' || true)
        if [ -n "$TMDB_ID" ]; then
            TMDB_URL="https://www.themoviedb.org/movie/${TMDB_ID}"
        fi
    fi
    [ -z "$MOVIE_TITLE" ] && MOVIE_TITLE="$BASENAME"

    # Generazione report HTML autonomo
    REPORT_HTML="/tmp/Report_FileBot_${BASENAME}.html"
    cat <<EOF > "$REPORT_HTML"
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <title>Report FileBot - $MOVIE_TITLE</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; padding: 24px; margin: 0; }
    .container { max-width: 800px; margin: 0 auto; background: #1e293b; border-radius: 12px; padding: 24px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); border: 1px solid #334155; }
    h1 { color: #f8fafc; font-size: 20px; margin-top: 0; }
    .badge { background: #10b981; color: white; padding: 4px 10px; border-radius: 9999px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
    table { width: 100%; border-collapse: collapse; margin-top: 16px; font-size: 13px; }
    th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #334155; }
    th { color: #94a3b8; width: 25%; font-weight: 600; }
    td { color: #f1f5f9; }
    pre { background: #0b1120; padding: 14px; border-radius: 8px; font-size: 11px; overflow-x: auto; color: #a5b4fc; border: 1px solid #1e293b; max-height: 400px; font-family: monospace; }
    a { color: #38bdf8; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <div style="display:flex; justify-content:space-between; align-items:center;">
      <h1>🎬 FileBot AMC Report</h1>
      <span class="badge">NORMALIZZATO</span>
    </div>
    <table>
      <tr><th>Film / Cartella</th><td><b>$MOVIE_TITLE</b></td></tr>
      $( [ -n "$TMDB_URL" ] && echo "<tr><th>TheMovieDB</th><td><a href='$TMDB_URL' target='_blank'>Scheda TMDb #$TMDB_ID ↗</a></td></tr>" )
      <tr><th>Sorgente</th><td><code>$SOURCE_DIR</code></td></tr>
      <tr><th>Destinazione</th><td><code>$TARGET_DIR</code></td></tr>
      <tr><th>File Finali</th><td><pre style="margin:0; background:transparent; border:none; padding:0; color:#38bdf8;">$FINAL_DEST_FILES</pre></td></tr>
      <tr><th>Elementi</th><td>$PROCESSED_ITEMS elaborati, $ERRORS errori</td></tr>
    </table>
    <h3 style="margin-top:24px; font-size:13px; color:#94a3b8; text-transform:uppercase;">Log Completo FileBot</h3>
    <pre>$(cat "$FILEBOT_LOG" 2>/dev/null || echo "Log non disponibile")</pre>
  </div>
</body>
</html>
EOF

    # Costruzione tabella dettagli per email HTML
    TABLE_ROWS="<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; width: 30%; border-bottom: 1px solid #f1f5f9;\">Film Riconosciuto</td>
  <td style=\"padding: 8px 12px; color: #0f172a; font-weight: 700; border-bottom: 1px solid #f1f5f9;\">$MOVIE_TITLE $( [ -n "$TMDB_URL" ] && echo "<a href='$TMDB_URL' style='color: #0284c7; text-decoration: none; font-size: 11px; margin-left: 6px;'>[TMDb ↗]</a>" )</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Sorgente</td>
  <td style=\"padding: 8px 12px; color: #1e293b; border-bottom: 1px solid #f1f5f9; font-family: monospace; font-size: 12px;\">$SOURCE_DIR</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Destinazione</td>
  <td style=\"padding: 8px 12px; color: #1e293b; border-bottom: 1px solid #f1f5f9; font-family: monospace; font-size: 12px;\">$TARGET_DIR</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Elementi</td>
  <td style=\"padding: 8px 12px; color: #1e293b; border-bottom: 1px solid #f1f5f9;\">$PROCESSED_ITEMS file elaborati</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Errori</td>
  <td style=\"padding: 8px 12px; color: $( [ \"$ERRORS\" -eq 0 ] && echo '#10b981' || echo '#ef4444' ); font-weight: 700; border-bottom: 1px solid #f1f5f9;\">$ERRORS</td>
</tr>"

    EXTRA_SECTION="<div style=\"margin-top: 18px; padding: 14px; background-color: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;\">
  <div style=\"font-size: 13px; font-weight: 700; color: #0f172a; margin-bottom: 8px;\">🎬 FileBot Hardlink & Artwork Details</div>
  <div style=\"font-size: 11px; font-family: monospace; color: #334155; word-break: break-all; background: #ffffff; padding: 8px 10px; border-radius: 4px; border: 1px solid #cbd5e1; margin-bottom: 8px;\">
    ${FIRST_DEST:-Nessun hardlink generato}
  </div>
  <div style=\"font-size: 11px; color: #64748b;\">
    📎 <b>Report Completo Allegato:</b> <code>$(basename "$REPORT_HTML")</code>
  </div>
</div>"

    STATUS_TEXT="Completato"
    STATUS_COLOR="#10b981"
    if [ "$ERRORS" -gt 0 ]; then
        STATUS_TEXT="Avviso Errori"
        STATUS_COLOR="#ef4444"
    fi

    EMAIL_HTML="$(build_html_email_template "🎬" "Elaborazione Completata: $MOVIE_TITLE" "Normalizzazione Video FileBot AMC" "$STATUS_TEXT" "$STATUS_COLOR" "$TABLE_ROWS" "$EXTRA_SECTION")"

    TEXT_MSG="⚠️ [Video Normalizzatore] Invio email di riepilogo fallito per '$BASENAME', ma l'elaborazione video è stata completata con successo."
    
    send_summary_email "$EMAIL_RECIPIENT" "🎬 [Video Normalizzatore] Elaborazione Completata: $MOVIE_TITLE" "$EMAIL_HTML" "$TEXT_MSG" "$REPORT_HTML"
fi

exit 0
