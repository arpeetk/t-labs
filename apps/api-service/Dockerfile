FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY main.go .
RUN go build -o api-service .

FROM alpine:3.23
RUN adduser -D -u 1000 app
USER app
COPY --from=build /src/api-service /api-service
EXPOSE 8080
ENTRYPOINT ["/api-service"]

