#!/bin/bash

# ————— Configurable via env vars —————
if [[ -n "$INFLUX_TOKEN_FILE" && -f "$INFLUX_TOKEN_FILE" ]]; then
  INFLUX_TOKEN=$(< "$INFLUX_TOKEN_FILE")
fi

INFLUX_URL="${INFLUX_URL:?required}"
INFLUX_ORG="${INFLUX_ORG:?required}"
INFLUX_BUCKET="${INFLUX_BUCKET:-internet}"
INFLUX_MEASUREMENT="${INFLUX_MEASUREMENT:-internet_status}"
PING_HOST="${PING_HOST:-1.1.1.1}"
PING_COUNT=1
PING_TIMEOUT="${PING_TIMEOUT:-2}"      # seconds to wait per ping
CHECK_INTERVAL="${CHECK_INTERVAL:-60}" # seconds between checks
LOG_FILE="${LOG_FILE:-./internet_monitor.log}"
CACHE_FILE="${CACHE_FILE:-./influx_cache.txt}"
# ————————————————————————————————————

WRITE_URL="$INFLUX_URL/api/v2/write?org=$INFLUX_ORG&bucket=$INFLUX_BUCKET&precision=s"

# ensure log & cache exist
touch "$LOG_FILE" "$CACHE_FILE"

echo "Starting Internet Monitor:"
echo " • PING $PING_HOST (timeout ${PING_TIMEOUT}s)"
echo " • Interval: ${CHECK_INTERVAL}s"
echo " • InfluxDB → $WRITE_URL (measurement: $INFLUX_MEASUREMENT)"
echo " • Local log → $LOG_FILE"
echo " • Cache file → $CACHE_FILE"
echo

while true; do
  TIMESTAMP=$(date +%s)

  # Run one ping, timeout after $PING_TIMEOUT
  # Output example: "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=23.4 ms"
  PING_OUT=$(ping -c${PING_COUNT} -W${PING_TIMEOUT} "$PING_HOST" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    STATUS=1
    # extract the time=XX.X part
    LATENCY=$(echo "$PING_OUT" | awk -F'time=' '/time=/{print $2}' | awk '{print $1}')
  else
    STATUS=0
    LATENCY=""  # no value if host unreachable
  fi

  # Build InfluxDB line protocol: two fields
  if [[ -n "$LATENCY" ]]; then
    DATA="${INFLUX_MEASUREMENT} status=${STATUS},latency_ms=${LATENCY} ${TIMESTAMP}"
  else
    DATA="${INFLUX_MEASUREMENT} status=${STATUS} ${TIMESTAMP}"
  fi

  if [[ $STATUS -eq 1 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Online — ${LATENCY:-n/a} ms" \
      | tee -a "$LOG_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Offline" \
      | tee -a "$LOG_FILE"
  fi

  echo "$DATA" >> "$CACHE_FILE"

  HTTP_RESPONSE="$(curl -w "%{http_code}" \
    -XPOST "$WRITE_URL" \
    -H "Authorization: Token $INFLUX_TOKEN" \
    -H "Content-Type: text/plain; charset=utf-8" \
    --data-binary @"$CACHE_FILE" \
    --silent --show-error || echo "CURL_ERR")"

  HTTP_CODE="${HTTP_RESPONSE: -3}"
  HTTP_BODY="${HTTP_RESPONSE:0:${#HTTP_RESPONSE}-3}"

  if [[ "$HTTP_CODE" == "204" ]]; then
    # success
    : > "$CACHE_FILE"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR writing to InfluxDB: code=$HTTP_CODE body='$HTTP_BODY'" \
      >> "$LOG_FILE"
  fi

  sleep "$CHECK_INTERVAL"
done
