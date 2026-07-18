#!/usr/bin/env bash
set -euo pipefail

# Script di normalizzazione CUE e splitting mega-FLAC tramite fmedia con notifiche Telegram
# USO: normalize.sh <SOURCE_PATH> [OUTPUT_DIR] [MEDIA_BASE]
#
# Esempio:
#   normalize.sh lidarr-classical/The Masterworks /media/downloads/lidarr-classical-normalize /media/downloads

MEDIA_BASE="${3:-/media/downloads}"

RAW_SOURCE="${1:-lidarr-classical/The Masterworks}"
RAW_TARGET="${2:-}"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

send_telegram() {
    local msg="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d parse_mode="HTML" \
            --data-urlencode "text=${msg}" >/dev/null 2>&1 || true
    fi
}

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

if [ ! -d "$SOURCE_DIR" ]; then
    ERR_MSG="❌ <b>[Normalizzazione Audio] Errore Sorgente</b>
La directory sorgente <code>$SOURCE_DIR</code> non esiste!"
    echo "❌ Errore: La directory sorgente '$SOURCE_DIR' non esiste!"
    send_telegram "$ERR_MSG"
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
    send_telegram "$SKIP_MSG"
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

    # CHECK PREVENTIVO: Verifichiamo se c'è un mega-audio file unico (.flac, .ape, .wv, .wav)
    MEGA_AUDIO_FILE=""
    audio_count="$(find "$cd_dir" -maxdepth 1 -type f \( -iname "*.flac" -o -iname "*.ape" -o -iname "*.wv" -o -iname "*.wav" \) ! -iname "*.backup" | wc -l)"

    if [ "$audio_count" -eq 1 ]; then
        MEGA_AUDIO_FILE="$(find "$cd_dir" -maxdepth 1 -type f \( -iname "*.flac" -o -iname "*.ape" -o -iname "*.wv" -o -iname "*.wav" \) ! -iname "*.backup" | head -n 1)"
    fi

    if [ -n "$MEGA_AUDIO_FILE" ]; then
        echo "🔍 Check OK: Trovato CD Rip con mega-audio file unico: '$(basename "$MEGA_AUDIO_FILE")'"
        echo "⚡ Esecuzione splitting tracce con fmedia in corso..."
        
        out_pattern="${cd_dir}/\$tracknumber - \$title.flac"
        if fmedia "$cue_file" --out="$out_pattern" --overwrite --notui; then
            echo "✅ Splitting fmedia completato con successo per '$(basename "$cd_dir")'."
            rm -f "$MEGA_AUDIO_FILE"
        else
            echo "❌ ERRORE: fmedia ha fallito lo splitting su '$cue_name'."
            ERRORS=$((ERRORS + 1))
            send_telegram "❌ <b>[Normalizzazione Audio] Errore Splitting</b>
<b>Cartella:</b> <code>$cd_dir</code>
<code>fmedia</code> ha fallito lo splitting sul file CUE <code>$cue_name</code>."
        fi
    else
        if [ "$audio_count" -gt 1 ]; then
            echo "ℹ️ Note: La cartella contiene già $audio_count tracce audio separate. Nessuno splitting mega-FLAC richiesto."
        else
            echo "❌ CHECK FALLITO: La cartella non contiene un CD Rip valido con mega-audio file abbinato al CUE!"
            ERRORS=$((ERRORS + 1))
            send_telegram "⚠️ <b>[Normalizzazione Audio] Check CD Rip Fallito</b>
<b>Cartella:</b> <code>$cd_dir</code>
Impossibile trovare un mega-audio file unico valido abbinato al file CUE."
        fi
    fi

    PROCESSED_CDS=$((PROCESSED_CDS + 1))
done < <(find "$TARGET_DIR" -type f -iname "*.cue" ! -name "*.backup" -print0)

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

send_telegram "$END_MSG"
