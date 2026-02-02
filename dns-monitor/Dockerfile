FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o dns-monitor .

FROM alpine:3.21
RUN apk --no-cache add ca-certificates
RUN adduser -D -u 65534 nonroot
WORKDIR /app
COPY --from=builder /app/dns-monitor .

USER nonroot
EXPOSE 8080
CMD ["./dns-monitor"]
