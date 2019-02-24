FROM golang:1.11.1-stretch as builder

WORKDIR /app-build
ADD ./ /app-build
RUN CGO_ENABLED=0 go build

FROM golang:alpine
RUN apk update && apk add ca-certificates && rm -rf /var/cache/apk/*
WORKDIR /app
COPY --from=builder /app-build/gosample /app
EXPOSE 443
EXPOSE 80
ENTRYPOINT "/app/gosample"