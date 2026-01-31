FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o failover-controller .

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/failover-controller .

# Install ca-certificates for HTTPS (registrar API calls).
RUN apk --no-cache add ca-certificates

# Create the default state persistence directory.
RUN mkdir -p /var/lib/failover-controller

EXPOSE 8080
CMD ["./failover-controller"]
