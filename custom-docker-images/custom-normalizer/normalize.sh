#!/usr/bin/env bash
set -euo pipefail

# Script di normalizzazione CUE e splitting mega-FLAC tramite fmedia con notifiche Telegram
# USO: normalize.sh <SOURCE_PATH> [OUTPUT_DIR] [MEDIA_BASE]
#
# Esempio:
#   normalize.sh lidarr-classical/The Masterworks /media/downloads/lidarr-classical-normalize /media/downloads

export HOME="${HOME:-/tmp}"
[ "$HOME" = "/" ] && export HOME=/tmp

MEDIA_BASE="${3:-/media/downloads}"
EMAIL_RECIPIENT="${4:-}"

RAW_SOURCE="${1:-lidarr-classical/The Masterworks}"
RAW_TARGET="${2:-}"

source "$(dirname "$0")/utils.sh"

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
        TARGET_BASE="$RAW_TARGET"
    else
        TARGET_BASE="${MEDIA_BASE}/${RAW_TARGET}"
    fi
    TARGET_BASE="${TARGET_BASE%/}"
    # Se il target non termina già col nome della cartella sorgente, appendiamo la sottocartella
    if [ "$(basename "$TARGET_BASE")" = "$BASENAME" ]; then
        TARGET_DIR="$TARGET_BASE"
    else
        TARGET_DIR="${TARGET_BASE}/${BASENAME}"
    fi
else
    TARGET_DIR="${SOURCE_DIR} - normalize"
fi

echo "=========================================================="
echo "  🎵 INIZIO PROCESSO DI NORMALIZZAZIONE E SPLITTING FMEDIA"
echo "=========================================================="
echo "Sorgente : '$SOURCE_DIR'"
echo "Target   : '$TARGET_DIR'"
echo "=========================================================="

if [ ! -e "$SOURCE_DIR" ]; then
    ERR_MSG="❌ <b>[Normalizzazione Audio] Errore Sorgente</b>
La directory sorgente <code>$SOURCE_DIR</code> non esiste!"
    echo "❌ Errore: La directory sorgente '$SOURCE_DIR' non esiste!"
    send_telegram "$ERR_MSG" "🎵 [Normalizzatore]"
    exit 1
elif [ ! -r "$SOURCE_DIR" ] || [ ! -x "$SOURCE_DIR" ]; then
    ERR_MSG="❌ <b>[Normalizzazione Audio] Errore Permessi</b>
Permessi insufficienti per accedere alla directory sorgente <code>$SOURCE_DIR</code>!"
    echo "❌ Errore: Permessi insufficienti per accedere alla directory '$SOURCE_DIR'!"
    send_telegram "$ERR_MSG" "🎵 [Normalizzatore]"
    exit 1
fi

# Controllo se la directory di destinazione esiste già
if [ -d "$TARGET_DIR" ]; then
    SKIP_MSG="⚠️ <b>[Normalizzazione Audio] Operazione Skippata</b>
<b>Target:</b> <code>$TARGET_DIR</code>
La directory di destinazione esiste già. L'elaborazione viene saltata per evitare sovrascritture."
    echo "=========================================================="
    echo "⚠️  WARNING: OPERAZIONE SKIPPATA!"
    echo "----------------------------------------------------------"
    echo "La directory di destinazione esiste già:"
    echo "  -> Target: '$TARGET_DIR'"
    echo "L'elaborazione viene saltata per evitare sovrascritture"
    echo "o duplicazioni indesiderate di dati."
    echo "=========================================================="
    send_telegram "$SKIP_MSG" "🎵 [Normalizzatore]"
    exit 0
fi

# 1. Creazione della cartella target e copia (preferenza Hardlink cp -al)
echo "📦 [1/2] Creazione struttura e copia file..."
mkdir -p "$TARGET_DIR"

if cp -al "$SOURCE_DIR/." "$TARGET_DIR/" 2>/dev/null; then
    echo "🔗 ✅ Copia effettuata con successo tramite HARDLINK (cp -al)."
else
    echo "⚠️ Hardlink non supportato o fallito. Esecuzione copia standard (cp -a)..."
    cp -a "$SOURCE_DIR/." "$TARGET_DIR/"
    echo "✅ Copia standard completata."
fi

# 2. Controllo CD Rip (presenza CUE + mega FLAC) ed estrazione tracce con fmedia
echo "🔧 [2/2] Ricerca ed elaborazione delle cartelle CD (gestione sub-dir annidate)..."
PROCESSED_CDS=0
ERRORS=0

while IFS= read -r -d '' cue_file; do
    cd_dir="$(dirname "$cue_file")"
    cue_name="$(basename "$cue_file")"
    echo ""
    echo "----------------------------------------------------------"
    echo "📁 Cartella CD : '$cd_dir'"
    echo "   File CUE    : '$cue_name'"

    # Pre-processing encoding & case matching via Python script
    python3 "$(dirname "$0")/preprocess_cue.py" "$cue_file"

    # Esecuzione di cuefix per correggere la sintassi del .cue
    cuefix -y "$cue_file" >/dev/null 2>&1 || true

    # CHECK PREVENTIVO: Verifichiamo se c'è un mega-audio file (usando la direttiva FILE nel CUE)
    MEGA_AUDIO_FILE=""
    file_directive_count="$(grep -c -i '^FILE ' "$cue_file" || true)"
    
    if [ "$file_directive_count" -eq 1 ]; then
        audio_filename="$(grep -im1 '^FILE ' "$cue_file" | awk -F '"' '{print $2}')"
        if [ -n "$audio_filename" ] && [ -f "$cd_dir/$audio_filename" ]; then
            MEGA_AUDIO_FILE="$cd_dir/$audio_filename"
        fi
    fi

    if [ -n "$MEGA_AUDIO_FILE" ]; then
        echo "🔍 Check OK: Trovato CD Rip con mega-audio file unico: '$(basename "$MEGA_AUDIO_FILE")'"
        echo "⚡ Esecuzione splitting tracce con fmedia in corso..."
        
        cue_base="${cue_name%.*}"
        out_pattern="${cd_dir}/${cue_base} - \$tracknumber - \$title.flac"
        if fmedia "$cue_file" --out="$out_pattern" --overwrite --notui; then
            echo "✅ Splitting fmedia completato con successo per '$(basename "$cd_dir")'."
            rm -f "$MEGA_AUDIO_FILE"
        else
            echo "❌ ERRORE: fmedia ha fallito lo splitting su '$cue_name'."
            ERRORS=$((ERRORS + 1))
            send_telegram "❌ <b>[Normalizzazione Audio] Errore Splitting</b>
<b>Cartella:</b> <code>$cd_dir</code>
<code>fmedia</code> ha fallito lo splitting sul file CUE <code>$cue_name</code>." "🎵 [Normalizzatore]"
        fi
    else
        if [ "$file_directive_count" -gt 1 ]; then
            echo "ℹ️ Note: Il file CUE referenzia $file_directive_count tracce audio. Nessuno splitting mega-FLAC richiesto."
        else
            echo "❌ CHECK FALLITO: Impossibile trovare un mega-audio file valido abbinato al CUE!"
            ERRORS=$((ERRORS + 1))
            send_telegram "⚠️ <b>[Normalizzazione Audio] Check CD Rip Fallito</b>
<b>Cartella:</b> <code>$cd_dir</code>
Impossibile trovare un mega-audio file unico valido abbinato al file CUE." "🎵 [Normalizzatore]"
        fi
    fi

    PROCESSED_CDS=$((PROCESSED_CDS + 1))
done < <(find "$TARGET_DIR" -type f -iname "*.cue" ! -name "*.backup" -print0)

# Inject internal TRACKNUMBER and DISCNUMBER tags into FLAC files for seamless tagging/matching
echo ""
echo "🏷️ Iniezione automatica metadati di traccia e disco (TRACKNUMBER/DISCNUMBER)..."
python3 "$(dirname "$0")/tag_flac_after_split.py" "$TARGET_DIR" || true

# 3. Tagging e Ottimizzazione con SongKong Premium per MinimServer/Musica Classica
SONGKONG_OUTPUT_LOG="/tmp/songkong_${BASENAME}.log"
SONGKONG_REPORT_FILE=""
SONG_LOADED="0"
SONG_MATCHED="0"

if [ -x "/opt/songkong/songkong.sh" ]; then
    mkdir -p "${HOME:-/tmp}/.songkong"
    if [ -f "/etc/songkong/license.properties" ]; then
        cp "/etc/songkong/license.properties" "${HOME:-/tmp}/.songkong/license.properties" 2>/dev/null || true
    fi
    echo ""
    echo "=========================================================="
    echo "🔍 [3/3] Esecuzione SongKong Premium in corso..."
    echo "=========================================================="
    echo "Avvio dell'ottimizzazione dei tag per MinimServer e Musica Classica..."
    
    # Invocazione di SongKong in modalità "Fix Songs" (-m) con interprete esplicito e cattura log
    if (cd /opt/songkong && bash ./songkong.sh -m "$TARGET_DIR" 2>&1 | tee "$SONGKONG_OUTPUT_LOG"); then
        echo "✅ SongKong ha completato la taggatura con successo."
    else
        echo "⚠️  Avviso: SongKong ha completato l'elaborazione (verificare eventuali warning)."
    fi

    # Estrazione del percorso nativo del report generato da SongKong
    RAW_REPORT=$(grep "Report Created:" "$SONGKONG_OUTPUT_LOG" 2>/dev/null | head -n 1 | awk -F 'Report Created:' '{print $2}' | tr -d '\r\n ' || true)
    if [ -n "$RAW_REPORT" ] && [ -f "$RAW_REPORT" ]; then
        SONGKONG_REPORT_FILE="$RAW_REPORT"
    fi

    # Estrazione metriche dal log di SongKong
    SONG_LOADED=$(grep "Songs loaded:" "$SONGKONG_OUTPUT_LOG" 2>/dev/null | head -n 1 | awk -F ':' '{print $2}' | tr -d '\r\n ' || echo "0")
    SONG_MATCHED=$(grep "Completed:" "$SONGKONG_OUTPUT_LOG" 2>/dev/null | head -n 1 | awk -F ':' '{print $2}' | tr -d '\r\n ' || echo "0")

    # Fallback rigoroso per localizzare il report escludendo webhelp e style
    if [ -z "$SONGKONG_REPORT_FILE" ]; then
        REPORT_BASE="${HOME:-/tmp}/.songkong/Reports"
        [ ! -d "$REPORT_BASE" ] && REPORT_BASE="/tmp/.songkong/Reports"
        [ ! -d "$REPORT_BASE" ] && REPORT_BASE="/root/.songkong/Reports"
        if [ -d "$REPORT_BASE" ]; then
            LATEST_DIR="$(find "$REPORT_BASE" -mindepth 1 -maxdepth 1 -type d ! -name "webhelp" ! -name "style" 2>/dev/null | sort -V | tail -n 1 || echo "")"
            if [ -n "$LATEST_DIR" ] && [ -d "$LATEST_DIR" ]; then
                SONGKONG_REPORT_FILE="$(find "$LATEST_DIR" -maxdepth 1 -name "*.html" ! -name "*_*" | head -n 1 || echo "")"
            fi
        fi
    fi

    if [ "${SONGKONG_VERBOSE:-false}" = "true" ] || [ "${SONGKONG_VERBOSE:-false}" = "1" ]; then
        echo "🔍 [SONGKONG_VERBOSE] Dump log dettagliati di SongKong:"
        for logfile in /tmp/.songkong/Logs/songkong_*.log; do
            if [ -f "$logfile" ]; then
                echo "--- START $logfile ---"
                cat "$logfile"
                echo "--- END $logfile ---"
            fi
        done
    fi
else
    echo "⚠️  Avviso: SongKong non è installato in questo container, salto la fase di tagging."
fi

END_MSG="🎉 <b>[Normalizzazione Audio] Elaborazione Completata</b>
<b>Sorgente:</b> <code>$SOURCE_DIR</code>
<b>Target:</b> <code>$TARGET_DIR</code>
<b>Cartelle CD elaborate:</b> <code>$PROCESSED_CDS</code>
<b>Errori riscontrati:</b> <code>$ERRORS</code>"

echo ""
echo "=========================================================="
echo "🎉 ELABORAZIONE COMPLETATA!"
echo "Cartelle CD elaborate : $PROCESSED_CDS"
echo "Errori riscontrati     : $ERRORS"
echo "Directory finale       : '$TARGET_DIR'"
echo "=========================================================="

# Assicuriamo permessi 777 per permettere modifiche/taggatura da SMB/NFS
chmod -R 777 "$TARGET_DIR" 2>/dev/null || true

send_telegram "$END_MSG" "🎵 [Normalizzatore]"

if [ -n "$EMAIL_RECIPIENT" ]; then
    # Preparazione dell'allegato autonomo con nome parlante
    ATTACHMENT_PATH=""
    if [ -n "$SONGKONG_REPORT_FILE" ] && [ -f "$SONGKONG_REPORT_FILE" ]; then
        CLEAN_ATTACHMENT="/tmp/Report_SongKong_${BASENAME}.html"
        cp "$SONGKONG_REPORT_FILE" "$CLEAN_ATTACHMENT"
        ATTACHMENT_PATH="$CLEAN_ATTACHMENT"
    fi

    # Costruzione tabella dettagli per email HTML
    TABLE_ROWS="<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; width: 30%; border-bottom: 1px solid #f1f5f9;\">Sorgente</td>
  <td style=\"padding: 8px 12px; color: #1e293b; border-bottom: 1px solid #f1f5f9; font-family: monospace; font-size: 12px;\">$SOURCE_DIR</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Destinazione</td>
  <td style=\"padding: 8px 12px; color: #1e293b; border-bottom: 1px solid #f1f5f9; font-family: monospace; font-size: 12px;\">$TARGET_DIR</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Cartelle CD</td>
  <td style=\"padding: 8px 12px; color: #1e293b; border-bottom: 1px solid #f1f5f9;\">$PROCESSED_CDS</td>
</tr>
<tr>
  <td style=\"padding: 8px 12px; font-weight: 600; color: #475569; border-bottom: 1px solid #f1f5f9;\">Errori</td>
  <td style=\"padding: 8px 12px; color: $( [ \"$ERRORS\" -eq 0 ] && echo '#10b981' || echo '#ef4444' ); font-weight: 700; border-bottom: 1px solid #f1f5f9;\">$ERRORS</td>
</tr>"

    EXTRA_SECTION="<div style=\"margin-top: 18px; padding: 14px; background-color: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;\">
  <div style=\"font-size: 13px; font-weight: 700; color: #0f172a; margin-bottom: 8px;\">🎵 SongKong Premium Metadata Engine</div>
  <table style=\"width: 100%; font-size: 12px; border-collapse: collapse;\">
    <tr>
      <td style=\"color: #64748b; padding: 4px 0;\">Tracce caricate:</td>
      <td style=\"font-weight: 600; color: #0f172a; text-align: right;\">${SONG_LOADED:-0}</td>
    </tr>
    <tr>
      <td style=\"color: #64748b; padding: 4px 0;\">Tracce elaborate / matchate:</td>
      <td style=\"font-weight: 600; color: #10b981; text-align: right;\">${SONG_MATCHED:-0}</td>
    </tr>
    $( [ -n "$ATTACHMENT_PATH" ] && echo "<tr><td colspan='2' style='padding-top: 8px; font-size: 11px; color: #64748b; border-top: 1px dashed #cbd5e1;'>📎 <b>Report Completo Allegato:</b> <code>$(basename "$ATTACHMENT_PATH")</code></td></tr>" )
  </table>
</div>"

    STATUS_TEXT="Completato"
    STATUS_COLOR="#10b981"
    if [ "$ERRORS" -gt 0 ]; then
        STATUS_TEXT="Avviso Errori"
        STATUS_COLOR="#ef4444"
    fi

    EMAIL_HTML="$(build_html_email_template "🎵" "Elaborazione Completata: $BASENAME" "Normalizzazione Audio & Taggatura Intelligente" "$STATUS_TEXT" "$STATUS_COLOR" "$TABLE_ROWS" "$EXTRA_SECTION")"

    TEXT_MSG="⚠️ [Normalizzatore] Invio email di riepilogo fallito per '$BASENAME', ma l'elaborazione audio e i tag sono stati completati con successo."
    
    send_summary_email "$EMAIL_RECIPIENT" "🎵 [Normalizzatore] Elaborazione Completata: $BASENAME" "$EMAIL_HTML" "$TEXT_MSG" "$ATTACHMENT_PATH"
fi

# Chiusura sempre con successo per Kubernetes (exit 0)
exit 0
