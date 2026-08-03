FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV MID_VERSION="australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106"

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    wget \
    unzip \
    curl \
    ca-certificates \
    net-tools \
    iputils-ping \
    procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN wget --no-check-certificate https://install.service-now.com/glide/distribution/builds/package/app-signed/mid-core/2026/06/12/mid-core.australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106.universal.universal.zip -O mid.zip \
    && unzip mid.zip \
    && rm mid.zip

WORKDIR /opt/agent

COPY entrypoint.sh /opt/agent/entrypoint.sh
RUN chmod +x /opt/agent/entrypoint.sh

ENTRYPOINT ["/opt/agent/entrypoint.sh"]
