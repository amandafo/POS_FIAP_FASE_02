FROM golang:1.21-alpine AS build

WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /bin/auth-service .

FROM alpine:3.20

RUN addgroup -S app && adduser -S app -G app
WORKDIR /app

COPY --from=build /bin/auth-service /app/auth-service

USER app
EXPOSE 8001

ENTRYPOINT ["/app/auth-service"]
