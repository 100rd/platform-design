FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o hello-world main.go

FROM alpine:3.21
RUN adduser -D -u 65534 nonroot
WORKDIR /app
COPY --from=builder /app/hello-world .
USER nonroot
EXPOSE 8080
ENTRYPOINT ["./hello-world"]

