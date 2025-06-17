FROM alpine

RUN apk add --no-cache tzdata curl bash

ENV TZ=Europe/Berlin

WORKDIR /app

COPY internet_monitor.sh .
RUN chmod +x internet_monitor.sh

HEALTHCHECK \
  --interval=60s \
  --timeout=10s \
  --start-period=30s \
  --retries=3 \
  CMD pgrep -f internet_monitor.sh || exit 1

CMD ["./internet_monitor.sh"]
