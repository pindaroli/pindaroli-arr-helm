ARG QBITTORRENT_VERSION="5.2.3_v2.0.13-ls468"
FROM lscr.io/linuxserver/qbittorrent:${QBITTORRENT_VERSION}

# Argomento per gestire facilmente la versione di fmedia
ARG FMEDIA_VERSION="1.23.1"

RUN \
    echo "**** Installazione dipendenze di sistema e Python ****" && \
    apk update && \
    apk add --no-cache \
    curl \
    xz \
    gcompat \
    bash \
    python3 \
    py3-pip \
    alsa-lib

RUN \
    echo "**** Installazione fmedia ****" && \
    curl -L -o /tmp/fmedia.tar.xz "https://downloads.sourceforge.net/project/fmedia/v${FMEDIA_VERSION}/fmedia-${FMEDIA_VERSION}-linux-amd64.tar.xz" && \
    tar -xf /tmp/fmedia.tar.xz -C /opt && \
    ln -s /opt/fmedia-1/fmedia /usr/local/bin/fmedia && \
    rm -rf /tmp/fmedia.tar.xz

RUN \
    echo "**** Installazione cuefix ****" && \
    pip3 install --no-cache-dir cuefix --break-system-packages

# Copia e installazione dello script di normalizzazione e del pre-processore python
COPY normalize.sh preprocess_cue.py /usr/local/bin/
RUN chmod +x /usr/local/bin/normalize.sh

RUN \
    echo "**** Pulizia finale ****" && \
    rm -rf /var/cache/apk/* ~/.cache/pip