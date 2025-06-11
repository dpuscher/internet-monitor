FROM alpine

RUN apk add --no-cache tzdata curl bash

ENV TZ=Europe/Berlin

WORKDIR /app

COPY internet_monitor.sh .
RUN chmod +x internet_monitor.sh

CMD ["./internet_monitor.sh"]
