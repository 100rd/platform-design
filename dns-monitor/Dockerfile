FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o dns-monitor .

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/dns-monitor .

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

EXPOSE 8080
CMD ["./dns-monitor"]
