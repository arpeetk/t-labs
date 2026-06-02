FROM golang:1.22-alpine AS build
WORKDIR /src
COPY main.go .
RUN go mod init hello-world && go build -o hello-world .

FROM alpine:3.19
RUN adduser -D -u 1000 app
USER app
COPY --from=build /src/hello-world /hello-world
EXPOSE 8080
ENTRYPOINT ["/hello-world"]
