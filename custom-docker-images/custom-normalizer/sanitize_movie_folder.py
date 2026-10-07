#!/usr/bin/env python3
# =============================================================================
# sanitize_movie_folder.py
# Engine di Sanificazione Cartelle e Versioni Multiple Film per Jellyfin
# =============================================================================
# Funzionalità:
# 1. Risoluzione input flessibile: nome cartella, path o nome file con estensione
# 2. Normalizzazione cartella genitore in 'Titolo (Anno) {tmdb-ID}' se non conforme
# 3. Analisi ffprobe per release legacy e rinomina a standard Jellyfin multi-versione
# 4. Sincronizzazione automatica sottotitoli (.srt / .sub)
# 5. Bonifica selettiva artwork duplicati (*-poster.jpg, *-backdrop.jpg, ecc.)
# 6. Refresh libreria Jellyfin via API REST
# =============================================================================

import os
import re
import sys
import json
import shutil
import argparse
import unicodedata
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

MEDIA_DIR = os.environ.get("MEDIA_DIR", "/mnt/oliraid/arrdata/media/movies")
JELLYFIN_URL = os.environ.get("JELLYFIN_URL", "http://10.10.20.50:8096")
JELLYFIN_TOKEN = os.environ.get("JELLYFIN_TOKEN", "7c80240c7a9b4326a8690ce140265a14")

VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".ts", ".m4v", ".m2ts", ".iso"}
SUBTITLE_EXTS = {".srt", ".sub", ".idx", ".vtt", ".ass", ".smi"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}

CANONICAL_FOLDER_RE = re.compile(r"^(.+?)\s*\((\d{4})\)\s*\{tmdb-(\d+)\}$")

CANONICAL_ARTWORK_NAMES = {
    "poster.jpg", "poster.jpeg", "poster.png",
    "folder.jpg", "folder.jpeg", "folder.png",
    "fanart.jpg", "fanart.jpeg", "fanart.png",
    "backdrop.jpg", "backdrop.jpeg", "backdrop.png",
    "backdrop2.jpg", "backdrop3.jpg",
    "logo.png", "clearart.png", "disc.png", "landscape.jpg", "landscape.png"
}

def get_ffprobe_bin():
    if os.path.exists("/mnt/oliraid/bin/ffprobe") and os.access("/mnt/oliraid/bin/ffprobe", os.X_OK):
        return "/mnt/oliraid/bin/ffprobe"
    return shutil.which("ffprobe")

def is_video_file(filename):
    return any(filename.lower().endswith(ext) for ext in VIDEO_EXTS)

def is_subtitle_file(filename):
    return any(filename.lower().endswith(ext) for ext in SUBTITLE_EXTS)

def clean_title_for_search(text):
    clean = re.sub(r'\[.*?\]|\{.*?\}', '', text)
    clean = re.sub(r'[\(\[\s\.-](19\d{2}|20\d{2})[\)\]\s\.-]?.*', '', clean)
    clean = unicodedata.normalize('NFKD', clean).encode('ASCII', 'ignore').decode('utf-8')
    clean = re.sub(r'[\.\-_\(\)]+', ' ', clean).strip().lower()
    clean = re.sub(r'^(the|a|an|il|la|lo|i|gli|le|un|uno|una)\s+', '', clean).strip()
    return clean

def extract_tmdb_and_year_from_text(text):
    tmdb_match = re.search(r'(?:tmdbid|tmdb)[-_](\d+)', text, re.IGNORECASE)
    tmdb_id = tmdb_match.group(1) if tmdb_match else None

    year_match = re.search(r'[\(\[\s\.-](19\d{2}|20\d{2})[\)\]\s\.-]?', text)
    year = year_match.group(1) if year_match else None

    return tmdb_id, year

def query_jellyfin_for_tmdb(title, year=None):
    if not JELLYFIN_URL or not JELLYFIN_TOKEN:
        return None, None, None

    query = urllib.parse.quote(title)
    url = f"{JELLYFIN_URL.rstrip('/')}/Items?searchTerm={query}&includeItemTypes=Movie&recursive=true"
    req = urllib.request.Request(
        url,
        headers={"Authorization": f'MediaBrowser Token="{JELLYFIN_TOKEN}"'}
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            items = data.get("Items", [])
            for item in items:
                prov = item.get("ProviderIds", {})
                tmdb_id = prov.get("Tmdb")
                prod_year = str(item.get("ProductionYear", ""))
                item_name = item.get("Name", "")
                if tmdb_id:
                    if year and prod_year and year == prod_year:
                        return tmdb_id, item_name, prod_year
                    elif not year:
                        return tmdb_id, item_name, prod_year
            if items:
                prov = items[0].get("ProviderIds", {})
                tmdb_id = prov.get("Tmdb")
                if tmdb_id:
                    return tmdb_id, items[0].get("Name", title), str(items[0].get("ProductionYear", year or ""))
    except Exception:
        pass
    return None, None, None

def find_target_folder(base_media_dir, user_input):
    base_path = Path(base_media_dir)
    raw_path = Path(user_input.strip())

    # 1. Se il percorso esiste direttamente
    if raw_path.exists():
        if raw_path.is_dir():
            return raw_path.resolve()
        elif raw_path.is_file():
            return raw_path.parent.resolve()

    # 2. Se esiste come percorso relativo dentro base_media_dir
    rel_path = base_path / user_input.strip().strip("'\"")
    if rel_path.exists():
        if rel_path.is_dir():
            return rel_path.resolve()
        elif rel_path.is_file():
            return rel_path.parent.resolve()

    input_clean = user_input.strip().strip("'\"")
    input_is_file = any(input_clean.lower().endswith(ext) for ext in VIDEO_EXTS)

    # 3. Se è stato passato un nome file con estensione (es. 'Trainspotting (1996).avi')
    if input_is_file:
        print(f"🔍 Ricerca della cartella genitore per il file '{input_clean}' in {base_media_dir}...")
        for entry in base_path.iterdir():
            if entry.is_dir():
                target_f = entry / input_clean
                if target_f.exists():
                    return entry.resolve()
                # Cerca case-insensitive
                for f in entry.iterdir():
                    if f.name.lower() == input_clean.lower():
                        return entry.resolve()

    # 4. Ricerca per nome cartella parziale o titolo
    for entry in base_path.iterdir():
        if entry.is_dir() and entry.name.lower() == input_clean.lower():
            return entry.resolve()

    # 5. Ricerca fuzzy per titolo e anno
    tmdb_in, year_in = extract_tmdb_and_year_from_text(input_clean)
    clean_in = clean_title_for_search(input_clean)
    for entry in base_path.iterdir():
        if not entry.is_dir(): continue
        tmdb_e, year_e = extract_tmdb_and_year_from_text(entry.name)
        if tmdb_in and tmdb_e and tmdb_in == tmdb_e:
            return entry.resolve()
        clean_e = clean_title_for_search(entry.name)
        if clean_in and clean_in == clean_e:
            if not year_in or not year_e or year_in == year_e:
                return entry.resolve()

    return None

def analyze_video_technical_specs(video_path):
    specs = {"res": "SD", "codec": "VIDEO"}
    ffprobe = get_ffprobe_bin()
    if not ffprobe or not os.path.exists(video_path):
        # Fallback euristico da estensione o nome
        if video_path.lower().endswith(".avi"):
            specs["codec"] = "XviD"
            specs["res"] = "576p"
        return specs

    cmd = [
        ffprobe, "-v", "quiet", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,codec_name",
        "-of", "json", str(video_path)
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
        data = json.loads(res.stdout)
        streams = data.get("streams", [])
        if streams:
            st = streams[0]
            w = st.get("width", 0)
            h = st.get("height", 0)
            cname = st.get("codec_name", "").lower()

            # Normalizzazione Risoluzione
            if h >= 2100 or w >= 3800:
                specs["res"] = "2160p"
            elif h >= 1000 or w >= 1900:
                specs["res"] = "1080p"
            elif h >= 700 or w >= 1200:
                specs["res"] = "720p"
            elif h >= 500 or (w >= 700 and h >= 400):
                specs["res"] = "576p"
            elif h >= 400:
                specs["res"] = "480p"
            else:
                specs["res"] = "SD"

            # Normalizzazione Codec
            if cname in ["xvid", "mpeg4", "msmpeg4v3"]:
                specs["codec"] = "XviD" if "xvid" in cname or video_path.lower().endswith(".avi") else "MPEG4"
            elif cname in ["h264", "avc", "avc1"]:
                specs["codec"] = "H264"
            elif cname in ["hevc", "h265"]:
                specs["codec"] = "HEVC"
            elif cname in ["vc1"]:
                specs["codec"] = "VC-1"
            elif cname:
                specs["codec"] = cname.upper()
    except Exception:
        pass
    return specs

def trigger_jellyfin_refresh():
    if not JELLYFIN_URL or not JELLYFIN_TOKEN:
        return False
    refresh_url = f"{JELLYFIN_URL.rstrip('/')}/Library/Refresh"
    print(f"\n📡 Invio notifica di refresh libreria a Jellyfin ({refresh_url})...")
    req = urllib.request.Request(
        refresh_url,
        data=b"",
        headers={
            "Authorization": f'MediaBrowser Token="{JELLYFIN_TOKEN}"',
            "Content-Length": "0"
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status in [200, 204]:
                print("   ✅ Refresh Jellyfin avviato con successo!")
                return True
            else:
                print(f"   ⚠️ Risposta Jellyfin: HTTP {resp.status}")
                return False
    except Exception as e:
        print(f"   ❌ Errore di connessione a Jellyfin: {e}")
        return False

def plan_sanitization(target_dir):
    plan = {
        "source_dir": str(target_dir),
        "target_dir": str(target_dir),
        "folder_action": "NOOP", # NOOP, RENAME_DIR, MERGE_DIR
        "canonical_folder_name": target_dir.name,
        "video_renames": [],
        "subtitle_renames": [],
        "artwork_purges": [],
        "nfo_purges": []
    }

    folder_name = target_dir.name
    m = CANONICAL_FOLDER_RE.match(folder_name)

    # 1. Verifica e Normalizzazione Cartella Genitore
    if not m:
        tmdb_id, year = extract_tmdb_and_year_from_text(folder_name)
        title = None

        # Cerca tmdb_id nei file video contenuti
        all_vids = [f for f in target_dir.iterdir() if f.is_file() and is_video_file(f.name)]
        for v in all_vids:
            v_tmdb, v_yr = extract_tmdb_and_year_from_text(v.name)
            if not tmdb_id and v_tmdb:
                tmdb_id = v_tmdb
            if not year and v_yr:
                year = v_yr
            m_v = re.match(r"^(.+?)\s*\((\d{4})\)", v.name)
            if m_v and not title:
                title = m_v.group(1).strip()

        if not title:
            m_dir = re.match(r"^(.+?)\s*\((\d{4})\)", folder_name)
            title = m_dir.group(1).strip() if m_dir else folder_name

        if not tmdb_id:
            print(f"🌐 Interrogazione Jellyfin per ricavare TMDb ID di '{title}'...")
            jf_tmdb, jf_title, jf_year = query_jellyfin_for_tmdb(title, year)
            if jf_tmdb:
                tmdb_id = jf_tmdb
                title = jf_title or title
                year = jf_year or year

        if tmdb_id and year:
            canonical_name = f"{title} ({year}) {{tmdb-{tmdb_id}}}"
            canonical_path = target_dir.parent / canonical_name
            plan["canonical_folder_name"] = canonical_name
            plan["target_dir"] = str(canonical_path)

            if canonical_path.exists() and canonical_path != target_dir:
                plan["folder_action"] = "MERGE_DIR"
            else:
                plan["folder_action"] = "RENAME_DIR"
        else:
            print(f"⚠️ Impossibile determinare TMDb ID per '{folder_name}'. La cartella manterrà il nome corrente.")
            plan["canonical_folder_name"] = folder_name
    else:
        plan["canonical_folder_name"] = folder_name

    canonical_prefix = plan["canonical_folder_name"]

    # 2. Scansione File Interni (File Video e Subtitles)
    existing_video_files = [f for f in target_dir.iterdir() if f.is_file() and is_video_file(f.name)]
    
    used_labels = set()
    # Rileva etichette già in uso nei video conformi
    for v in existing_video_files:
        if v.name.startswith(f"{canonical_prefix} - ["):
            label_match = re.search(r' - \[(.+?)\]', v.name)
            if label_match:
                used_labels.add(label_match.group(1))

    for v in existing_video_files:
        v_name = v.name
        # Se già conforme e inizia col prefisso canonico esatto:
        if v_name.startswith(f"{canonical_prefix} - ["):
            continue

        specs = analyze_video_technical_specs(str(v))
        base_label = f"{specs['res']} {specs['codec']}"
        label = base_label
        counter = 2
        while label in used_labels:
            label = f"{base_label} v{counter}"
            counter += 1
        used_labels.add(label)

        ext = v.suffix.lower()
        new_video_stem = f"{canonical_prefix} - [{label}]"
        new_video_name = f"{new_video_stem}{ext}"
        new_video_path = Path(plan["target_dir"]) / new_video_name

        plan["video_renames"].append({
            "src": str(v),
            "dst": str(new_video_path),
            "label": label,
            "old_stem": v.stem,
            "new_stem": new_video_stem
        })

        # Cerca sottotitoli associati a questo vecchio video
        for f in target_dir.iterdir():
            if f.is_file() and is_subtitle_file(f.name):
                if f.name.startswith(v.stem):
                    sub_suffix = f.name[len(v.stem):]
                    new_sub_name = f"{new_video_stem}{sub_suffix}"
                    new_sub_path = Path(plan["target_dir"]) / new_sub_name
                    plan["subtitle_renames"].append({
                        "src": str(f),
                        "dst": str(new_sub_path),
                        "old_name": f.name,
                        "new_name": new_sub_name
                    })

    # 3. Identificazione Artwork Ridondanti da Eliminare
    for f in target_dir.iterdir():
        if not f.is_file(): continue
        f_lower = f.name.lower()

        # NFO da eliminare (pattern rule)
        if f_lower.endswith(".nfo"):
            plan["nfo_purges"].append(str(f))
            continue

        if any(f_lower.endswith(ext) for ext in IMAGE_EXTS):
            # Preserva i canonici di cartella
            if f_lower in CANONICAL_ARTWORK_NAMES:
                continue

            # Se è un artwork con prefisso file (termina con -poster, -backdrop, ecc.)
            if re.search(r'-(poster|backdrop|landscape|logo|fanart)\.(jpg|jpeg|png|webp)$', f_lower):
                plan["artwork_purges"].append(str(f))

    return plan

def main():
    parser = argparse.ArgumentParser(description="Sanifica cartelle e versioni multiple di film per Jellyfin")
    parser.add_argument("target", nargs="?", default="", help="Nome cartella, path o nome file con estensione")
    parser.add_argument("--media-dir", default=MEDIA_DIR, help=f"Directory principale film (default: {MEDIA_DIR})")
    parser.add_argument("--apply", action="store_true", help="Applica le modifiche (default: dry-run)")
    parser.add_argument("--dry-run", action="store_true", help="Forza simulazione senza modifiche")
    parser.add_argument("--no-refresh", action="store_true", help="Disabilita il refresh di Jellyfin")
    args = parser.parse_args()

    user_input = args.target.strip()
    if not user_input:
        if sys.stdin.isatty():
            try:
                print("==================================================================")
                print("  🎬 Sanificazione Versioni Multiple & Cartelle Film Jellyfin     ")
                print("==================================================================")
                user_input = input("👉 Inserisci il nome della cartella o del file film con estensione: ").strip()
            except (KeyboardInterrupt, EOFError):
                print("\nOperazione annullata.")
                sys.exit(0)
        else:
            print("❌ Errore: Nessun target specificato in modalità non-interattiva.")
            sys.exit(1)

    if not user_input:
        print("❌ Errore: Target non specificato.")
        sys.exit(1)

    target_dir = find_target_folder(args.media_dir, user_input)
    if not target_dir:
        print(f"❌ Errore: Impossibile trovare la cartella o il file per '{user_input}' in {args.media_dir}.")
        sys.exit(1)

    print("==================================================================")
    print("  🎬 ANALISI SANIFICAZIONE FILM JELLYFIN                          ")
    print("==================================================================")
    print(f"📂 Cartella Rilevata : {target_dir}")

    plan = plan_sanitization(target_dir)

    print(f"🏷️  Nome Canonico    : {plan['canonical_folder_name']}")
    if plan["folder_action"] != "NOOP":
        print(f"📁 Azione Cartella   : [{plan['folder_action']}] -> {plan['target_dir']}")
    else:
        print(f"📁 Azione Cartella   : [INVARIATA (CONFORME)]")

    print("\n--- 📽️  FILE VIDEO ---")
    if plan["video_renames"]:
        for vr in plan["video_renames"]:
            print(f"  🔹 Rinomina Versione [{vr['label']}]:")
            print(f"     Da: {os.path.basename(vr['src'])}")
            print(f"     A : {os.path.basename(vr['dst'])}")
    else:
        print("  ✓ Tutti i file video sono già conformi alla nomenclatura multi-versione.")

    print("\n--- 💬 SOTTOTITOLI ---")
    if plan["subtitle_renames"]:
        for sr in plan["subtitle_renames"]:
            print(f"  🔹 Rinomina Sub: {sr['old_name']} -> {sr['new_name']}")
    else:
        print("  ✓ Nessun sottotitolo da rinominare.")

    print("\n--- 🖼️  BONIFICA ARTWORK DUPLICATI ---")
    if plan["artwork_purges"]:
        for ap in plan["artwork_purges"]:
            print(f"  🗑️  Rimozione Artwork Duplicato: {os.path.basename(ap)}")
    else:
        print("  ✓ Nessun artwork duplicato con prefisso video rilevato.")

    if plan["nfo_purges"]:
        print("\n--- 📄 BONIFICA NFO ---")
        for np in plan["nfo_purges"]:
            print(f"  🗑️  Rimozione .nfo: {os.path.basename(np)}")

    # Determinazione esecuzione
    execute_now = False
    has_changes = bool(plan["folder_action"] != "NOOP" or plan["video_renames"] or plan["subtitle_renames"] or plan["artwork_purges"] or plan["nfo_purges"])

    if not has_changes:
        print("\n==================================================================")
        print("✅ La cartella e i file sono già perfettamente conformi! Nessuna azione necessaria.")
        print("==================================================================")
        if not args.no_refresh:
            trigger_jellyfin_refresh()
        return

    if args.apply and not args.dry_run:
        execute_now = True
    elif sys.stdin.isatty() and not args.dry_run:
        try:
            confirm = input("\n🚀 Vuoi procedere con l'applicazione reale delle modifiche? [s/N]: ")
            if confirm.strip().lower() in ['s', 'si', 'y', 'yes']:
                execute_now = True
        except (KeyboardInterrupt, EOFError):
            execute_now = False

    if not execute_now:
        print("\n==================================================================")
        print("ℹ️  SIMULAZIONE COMPLETATA (DRY-RUN) — Nessun file è stato modificato.")
        print("Per applicare realmente le modifiche, usa il flag --apply o conferma al prompt.")
        print("==================================================================")
        return

    # ESECUZIONE REALE
    print("\n==================================================================")
    print("🚀 ESECUZIONE REALE: Applicazione modifiche in corso...")
    print("==================================================================")

    # 1. Rinomina / Merge Cartella
    final_dir = Path(plan["target_dir"])
    if plan["folder_action"] == "RENAME_DIR":
        print(f"  [REN_DIR] {target_dir.name} -> {final_dir.name}")
        os.rename(str(target_dir), str(final_dir))
    elif plan["folder_action"] == "MERGE_DIR":
        print(f"  [MERGE_DIR] Spostamento file da {target_dir.name} a {final_dir.name}...")
        for item in target_dir.iterdir():
            dest = final_dir / item.name
            if not dest.exists():
                shutil.move(str(item), str(dest))
        shutil.rmtree(str(target_dir), ignore_errors=True)

    # 2. Rinomina Video
    for vr in plan["video_renames"]:
        src_p = Path(vr["src"])
        dst_p = Path(vr["dst"])
        # Se la cartella è stata rinominata o spostata, correggi il path sorgente
        if plan["folder_action"] == "RENAME_DIR":
            src_p = final_dir / src_p.name
        elif plan["folder_action"] == "MERGE_DIR":
            src_p = final_dir / src_p.name

        if src_p.exists():
            print(f"  [REN_VID] {src_p.name} -> {dst_p.name}")
            os.rename(str(src_p), str(dst_p))

    # 3. Rinomina Sottotitoli
    for sr in plan["subtitle_renames"]:
        src_p = Path(sr["src"])
        dst_p = Path(sr["dst"])
        if plan["folder_action"] in ["RENAME_DIR", "MERGE_DIR"]:
            src_p = final_dir / src_p.name

        if src_p.exists():
            print(f"  [REN_SUB] {src_p.name} -> {dst_p.name}")
            os.rename(str(src_p), str(dst_p))

    # 4. Bonifica Artwork
    for ap in plan["artwork_purges"]:
        p = Path(ap)
        if plan["folder_action"] in ["RENAME_DIR", "MERGE_DIR"]:
            p = final_dir / p.name
        if p.exists():
            print(f"  [DEL_ART] Eliminazione artwork duplicato: {p.name}")
            os.remove(str(p))

    # 5. Bonifica NFO
    for np in plan["nfo_purges"]:
        p = Path(np)
        if plan["folder_action"] in ["RENAME_DIR", "MERGE_DIR"]:
            p = final_dir / p.name
        if p.exists():
            print(f"  [DEL_NFO] Eliminazione .nfo: {p.name}")
            os.remove(str(p))

    print("\n==================================================================")
    print("✅ Tutte le operazioni sono state completate con successo!")
    print("==================================================================")

    if not args.no_refresh:
        trigger_jellyfin_refresh()

if __name__ == "__main__":
    main()
