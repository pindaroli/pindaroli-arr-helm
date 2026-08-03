# Custom Docker MID Server Image

Questa cartella raccoglie i sorgenti per la build dell'immagine Docker personalizzata del MID Server ServiceNow basata sulla release ufficiale **Australia Patch 3**.

## Versione ServiceNow MID
- **Buildstamp**: `australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106`

## Tag Docker Registry
- `lgp1985/sn-mid-server:australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106`
- `lgp1985/sn-mid-server:latest`

## Comandi per Build & Push

```bash
cd custom-docker-images/custom-docker-MID

# Build dell'immagine Docker
docker build -t lgp1985/sn-mid-server:australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106 -t lgp1985/sn-mid-server:latest .

# Push sul registry Docker Hub
docker push lgp1985/sn-mid-server:australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106
docker push lgp1985/sn-mid-server:latest
```
