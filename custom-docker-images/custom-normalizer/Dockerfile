FROM debian:bookworm-slim

# Argomento per gestire facilmente la versione di fmedia
ARG FMEDIA_VERSION="1.23.1"

# 1. Installa le dipendenze di sistema minime e pip3 per cuefix
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    ffmpeg \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# 2. Scarica e installa fmedia da SourceForge (sorgente ufficiale funzionante)
RUN curl -L "https://downloads.sourceforge.net/project/fmedia/v${FMEDIA_VERSION}/fmedia-${FMEDIA_VERSION}-linux-amd64.tar.xz" -o fmedia.tar.xz \
    && tar Jxf fmedia.tar.xz -C /usr/local \
    && ln -s /usr/local/fmedia-1/fmedia /usr/local/bin/fmedia \
    && rm fmedia.tar.xz

# 3. Installa cuefix per la normalizzazione dei file CUE
RUN pip3 install --no-cache-dir cuefix --break-system-packages

# 4. Copia lo script di normalizzazione direttamente all'interno dell'immagine
COPY normalize.sh /app/normalize.sh
RUN chmod +x /app/normalize.sh

WORKDIR /app
ENTRYPOINT ["/app/normalize.sh"]
