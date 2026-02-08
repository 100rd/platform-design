FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o failover-controller .

FROM alpine:3.23
RUN apk --no-cache add ca-certificates
RUN adduser -D -u 65534 nonroot
RUN mkdir -p /var/lib/failover-controller && chown nonroot:nonroot /var/lib/failover-controller
WORKDIR /app
COPY --from=builder /app/failover-controller .

USER nonroot
EXPOSE 8080
CMD ["./failover-controller"]
