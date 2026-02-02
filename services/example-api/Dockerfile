FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o api .

FROM alpine:3.21
RUN adduser -D -u 65534 nonroot
WORKDIR /app
COPY --from=builder /app/api .
USER nonroot
EXPOSE 8080
CMD ["./api"]
