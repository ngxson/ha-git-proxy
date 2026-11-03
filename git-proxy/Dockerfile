FROM alpine:3.22

RUN apk add --no-cache nginx jq ca-certificates

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
