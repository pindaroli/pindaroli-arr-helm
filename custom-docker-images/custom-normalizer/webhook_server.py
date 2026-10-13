#!/usr/bin/env python3
import http.server
import socketserver
import urllib.parse
import urllib.request
import urllib.error
import subprocess
import threading
import sys
import os

def trigger_jellyfin_refresh(folder_id="f137a2dd21bbc1b99aa5c0f6bf02a805"):
    """Innesca lo scan della libreria su Jellyfin (mirato a Movies o generale)."""
    jellyfin_url = os.environ.get("JELLYFIN_URL", "http://jellyfin:8096").rstrip('/')
    token = os.environ.get("JELLYFIN_TOKEN", "7c80240c7a9b4326a8690ce140265a14")
    headers = {
        "Authorization": f'MediaBrowser Client="FileBot", Device="Server", DeviceId="filebot-normalizer", Version="1.0.0", Token="{token}"',
        "Content-Length": "0"
    }

    url = f"{jellyfin_url}/Items/{folder_id}/Refresh" if folder_id else f"{jellyfin_url}/Library/Refresh"
    print(f"📡 Innesco scan libreria su Jellyfin ({url})...")
    req = urllib.request.Request(url, data=b"", headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status in [200, 204]:
                print("✅ Scan libreria Jellyfin avviato con successo!")
                return True
            else:
                print(f"⚠️ Risposta Jellyfin: HTTP {resp.status}")
    except Exception as e:
        print(f"⚠️ Refresh mirato fallito ({e}), fallback a refresh generale libreria...")
        try:
            fallback_req = urllib.request.Request(f"{jellyfin_url}/Library/Refresh", data=b"", headers=headers, method="POST")
            with urllib.request.urlopen(fallback_req, timeout=10) as resp:
                if resp.status in [200, 204]:
                    print("✅ Scan generale libreria Jellyfin avviato con successo!")
                    return True
        except Exception as e2:
            print(f"❌ Errore innesco scan Jellyfin: {e2}")
    return False

CONFIG_FILE = os.environ.get("CATEGORIES_CONFIG", "/app/categories.yaml")

def parse_simple_yaml(text):
    """Parser YAML minimale e resiliente senza dipendenze esterne."""
    data = {}
    current_section = None
    current_key = None
    for line in text.splitlines():
        line = line.rstrip()
        if not line or line.strip().startswith('#'):
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if ':' in stripped:
            k, v = stripped.split(':', 1)
            k = k.strip()
            v = v.strip()
            if indent == 0:
                current_section = k
                data[current_section] = {}
            elif indent == 2:
                current_key = k
                if current_section:
                    if v:
                        data[current_section][current_key] = v
                    else:
                        data[current_section][current_key] = {}
            elif indent >= 4:
                if current_section and current_key and isinstance(data[current_section].get(current_key), dict):
                    if v.lower() == 'true':
                        v = True
                    elif v.lower() == 'false':
                        v = False
                    data[current_section][current_key][k] = v
    return data

def load_category_config():
    """Carica la configurazione delle categorie da file YAML (o JSON fallback)."""
    if not os.path.exists(CONFIG_FILE):
        return {}
    try:
        import yaml
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f) or {}
    except ImportError:
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                content = f.read()
            parsed = parse_simple_yaml(content)
            if parsed:
                return parsed
            import json
            return json.loads(content) or {}
        except Exception as e:
            print(f"⚠️ Errore caricamento {CONFIG_FILE} con parser fallback: {e}")
    except Exception as e:
        print(f"⚠️ Errore caricamento {CONFIG_FILE} come YAML: {e}")
    return {}

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/hooks/normalize':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')
            params = urllib.parse.parse_qs(post_data)

            path = params.get('path', [''])[0]
            category = params.get('category', [''])[0]
            target_output = params.get('target', [''])[0]

            if not path or not category:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Missing path or category")
                return

            config = load_category_config()
            configured_categories = config.get("categories", {})

            # Determiniamo se la categoria e' autorizzata
            cat_config = configured_categories.get(category)
            if not cat_config:
                # Fallback cablato di emergenza solo per le categorie autorizzate
                if category == "video-filebot":
                    cat_config = {"script": "/app/normalize-video.sh", "target": "/media/movies", "jellyfin_refresh": True}
                elif category == "lidarr-classical" or "classical" in category:
                    cat_config = {"script": "/app/normalize.sh", "target": "/media/classical", "jellyfin_refresh": False}
                elif category == "lidarr":
                    cat_config = {"script": "/app/normalize.sh", "target": "/media/music", "jellyfin_refresh": False}

            # Se la categoria non e' censita (es. pirn, radarr, sonarr), salta silenziosamente
            if not cat_config:
                print(f"ℹ️ [ALLOWLIST SKIP] Categoria '{category}' non censita per la normalizzazione. Skip.")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(f"Category '{category}' ignored (no normalization configured)".encode('utf-8'))
                return

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Processing started in background")

            # Start in background
            def run_script():
                nonlocal target_output
                script = cat_config.get("script", "/app/normalize.sh")
                if not target_output:
                    target_output = cat_config.get("target", "/media/music")
                refresh_jellyfin = cat_config.get("jellyfin_refresh", False)

                email_recipient = os.environ.get("EMAIL_RECIPIENT", "")

                cmd = [script, path, target_output, "/media", email_recipient]
                print(f"Running: {' '.join(cmd)}")
                try:
                    subprocess.run(cmd, check=True)
                    # Scatena automaticamente lo scan della libreria Movies su Jellyfin
                    if refresh_jellyfin:
                        trigger_jellyfin_refresh("f137a2dd21bbc1b99aa5c0f6bf02a805")
                except Exception as e:
                    print(f"Error: {e}")

            threading.Thread(target=run_script).start()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    PORT = 9000
    with socketserver.TCPServer(("", PORT), WebhookHandler) as httpd:
        print(f"Serving at port {PORT}")
        httpd.serve_forever()
