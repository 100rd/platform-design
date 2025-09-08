FROM golang:1.22-alpine as builder
WORKDIR /app
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o hello-world main.go

FROM alpine:3.20
WORKDIR /root/
COPY --from=builder /app/hello-world .
EXPOSE 8080
ENTRYPOINT ["./hello-world"]

