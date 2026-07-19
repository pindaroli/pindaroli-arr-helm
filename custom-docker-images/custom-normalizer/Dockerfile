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
    openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# 2. Scarica e installa fmedia da SourceForge (sorgente ufficiale funzionante)
RUN curl -L "https://downloads.sourceforge.net/project/fmedia/v${FMEDIA_VERSION}/fmedia-${FMEDIA_VERSION}-linux-amd64.tar.xz" -o fmedia.tar.xz \
    && tar Jxf fmedia.tar.xz -C /usr/local \
    && ln -s /usr/local/fmedia-1/fmedia /usr/local/bin/fmedia \
    && sed -i 's/mod "dbussleep"/#mod "dbussleep"/g' /usr/local/fmedia-1/fmedia.conf \
    && rm fmedia.tar.xz

# 3. Installa cuefix per la normalizzazione dei file CUE
RUN pip3 install --no-cache-dir cuefix --break-system-packages

# 4. Scarica e installa SongKong headless (versione Premium/CommandLine)
RUN curl -L "https://www.jthink.net/songkong/downloads/current/songkong-linux-headless.tgz" -o songkong.tgz \
    && tar zxf songkong.tgz -C /opt \
    && ln -s /opt/songkong/songkong.sh /usr/local/bin/songkong \
    && rm songkong.tgz

# Creazione cartella preferenze di SongKong per montaggio licenza
RUN mkdir -p /root/.songkong

# 5. Copia lo script di normalizzazione e il pre-processore python
COPY normalize.sh preprocess_cue.py /app/
RUN chmod +x /app/normalize.sh

WORKDIR /app
ENTRYPOINT ["/app/normalize.sh"]
