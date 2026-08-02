#!/usr/bin/env bash
set -euo pipefail

# Script di normalizzazione Video tramite FileBot con notifiche Telegram
# USO: normalize-video.sh <SOURCE_PATH> [OUTPUT_DIR] [MEDIA_BASE]
#
# Esempio:
#   normalize-video.sh radarr/Movies /media/movies /media

export HOME="${HOME:-/tmp}"
[ "$HOME" = "/" ] && export HOME=/tmp

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

if [ -f "/root/.filebot/license.psm" ]; then
    echo "🔑 Licenza FileBot trovata."
else
    echo "⚠️  Attenzione: Nessuna licenza FileBot trovata in /root/.filebot/license.psm. Alcune funzionalità di rename potrebbero fallire."
fi

mkdir -p "$TARGET_DIR"

PROCESSED_ITEMS=0
ERRORS=0

process_filebot() {
    local src="$1"
    echo "----------------------------------------------------------"
    echo "📽️  Elaborazione: '$src'"
    
    if filebot -script fn:amc "$src" \
        --output "$TARGET_DIR" \
        --action hardlink \
        --conflict override \
        -non-strict \
        --db TheMovieDB \
        --lang it \
        --def "movieFormat={n} ({y}) [tmdbid-{id}]/{n} ({y}) [tmdbid-{id}] - [{vf} {vc}]" \
        --def artwork=y nfo=y \
        --def ignore="subrip,sample"; then
        echo "✅ Elaborazione completata per '$(basename "$src")'."
        PROCESSED_ITEMS=$((PROCESSED_ITEMS + 1))
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
    # Se sorgente contiene directory multiple, considera solo i film contenuti della subdir di primo livello
    SUBDIRS=$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
    
    if [ "$SUBDIRS" -gt 0 ]; then
        echo "📁 Trovate $SUBDIRS sottocartelle di primo livello. Elaborazione in corso..."
        # Usare null-byte separator per gestire file con spazi e iterare le subdirs
        while IFS= read -r -d '' dir; do
            process_filebot "$dir"
        done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
    else
        echo "📄 Nessuna sottocartella trovata. Elaborazione della directory principale come singola entità."
        process_filebot "$SOURCE_DIR"
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

if [ -n "$EMAIL_RECIPIENT" ]; then
    EMAIL_BODY="🎬 PROCESSO DI NORMALIZZAZIONE VIDEO COMPLETATO

Dettagli dell'elaborazione:
----------------------------------------------------------
Sorgente: $SOURCE_DIR
Destinazione: $TARGET_DIR
Elementi elaborati: $PROCESSED_ITEMS
Errori riscontrati: $ERRORS
----------------------------------------------------------

Servizio di notifica automatico K8s normalizer."

    TEXT_MSG="⚠️ [Video Normalizzatore] Invio email di riepilogo fallito per '$BASENAME', ma l'elaborazione video è stata completata con successo."
    
    send_summary_email "$EMAIL_RECIPIENT" "🎬 [Video Normalizzatore] Elaborazione Completata: $BASENAME" "$EMAIL_BODY" "$TEXT_MSG" ""
fi

exit 0
