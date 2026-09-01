FROM debian:bookworm-slim

# Argomento per gestire facilmente la versione di fmedia
ARG FMEDIA_VERSION="1.23.1"

# 1. Installa le dipendenze di sistema minime e pip3 per cuefix/apprise
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    ffmpeg \
    xz-utils \
    openjdk-17-jre-headless \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# 2. Scarica e installa fmedia da SourceForge (sorgente ufficiale funzionante)
RUN curl -L "https://downloads.sourceforge.net/project/fmedia/v${FMEDIA_VERSION}/fmedia-${FMEDIA_VERSION}-linux-amd64.tar.xz" -o fmedia.tar.xz \
    && tar Jxf fmedia.tar.xz -C /usr/local \
    && ln -s /usr/local/fmedia-1/fmedia /usr/local/bin/fmedia \
    && sed -i 's/mod "dbussleep"/#mod "dbussleep"/g' /usr/local/fmedia-1/fmedia.conf \
    && rm fmedia.tar.xz

# 3. Installa cuefix, apprise e mutagen per notifiche e taggatura
RUN pip3 install --no-cache-dir cuefix apprise mutagen --break-system-packages

# 4. Scarica e installa SongKong headless (versione Premium/CommandLine)
RUN curl -L "https://www.jthink.net/songkong/downloads/current/songkong-linux-headless.tgz" -o songkong.tgz \
    && tar zxf songkong.tgz -C /opt \
    && rm songkong.tgz

# Creazione cartella preferenze di SongKong per montaggio licenza
RUN mkdir -p /root/.songkong

# 5. Installa FileBot via APT repository ufficiale
RUN apt-key adv --fetch-keys https://raw.githubusercontent.com/filebot/plugins/master/gpg/maintainer.pub \
    && echo "deb [arch=all] https://get.filebot.net/deb/ universal main" > /etc/apt/sources.list.d/filebot.list \
    && apt-get update \
    && apt-get install -y filebot \
    && rm -rf /var/lib/apt/lists/*

# Creazione cartella per configurazione e licenza di FileBot
RUN mkdir -p /root/.filebot

# 6. Copia script di normalizzazione (audio e video) e i pre/post-processori python
COPY normalize.sh normalize-video.sh utils.sh preprocess_cue.py tag_flac_after_split.py /app/
RUN chmod +x /app/normalize.sh /app/normalize-video.sh /app/utils.sh /app/tag_flac_after_split.py

WORKDIR /app
# L'entrypoint è stato rimosso per permettere l'override agevole dal Job Kubernetes.
# Il comando di default verrà specificato nei manifest.
