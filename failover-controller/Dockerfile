FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY . .
# Copy shared storage code from monitor if it was a real repo
# COPY ../dns-monitor/storage.go . 
# For this demo, we assume storage.go is duplicated or shared via module

RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o failover-controller .

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/failover-controller .

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

EXPOSE 8080
CMD ["./failover-controller"]
