#!/usr/bin/env bash
set -e

URL="${MID_INSTANCE_URL:-$SN_URL}"
USERNAME="${MID_INSTANCE_USERNAME:-$SN_USER}"
PASSWORD="${MID_INSTANCE_PASSWORD:-$SN_PASSWD}"
NAME="${MID_SERVER_NAME:-$SN_MID_NAME}"

if [ -n "$URL" ]; then
  if [[ "$URL" != http* ]]; then
    URL="https://${URL}.service-now.com/"
  fi
  if [[ "$URL" != */ ]]; then
    URL="${URL}/"
  fi
  sed -i "s|name=\"url\" value=\".*\"|name=\"url\" value=\"${URL}\"|g" /opt/agent/config.xml
fi

if [ -n "$USERNAME" ]; then
  sed -i "s|name=\"mid.instance.username\" value=\".*\"|name=\"mid.instance.username\" value=\"${USERNAME}\"|g" /opt/agent/config.xml
fi

if [ -n "$PASSWORD" ]; then
  sed -i "s|name=\"mid.instance.password\" value=\".*\"|name=\"mid.instance.password\" value=\"${PASSWORD}\"|g" /opt/agent/config.xml
fi

if [ -n "$NAME" ]; then
  sed -i "s|name=\"name\" value=\".*\"|name=\"name\" value=\"${NAME}\"|g" /opt/agent/config.xml
fi

echo "Starting ServiceNow MID Server (australia-02-11-2026__patch3-05-25-2026_06-12-2026_1106)..."
bin/mid.sh start
exec tail -f logs/agent0.log.0
