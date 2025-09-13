FROM rust:1.70 as builder

WORKDIR /app/relay
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN apt-get update && apt-get install -y pkg-config libssl-dev
RUN cargo build --release

FROM rust:1.70

RUN apt-get update && apt-get install -y pkg-config libssl-dev sqlite3

WORKDIR /app
COPY --from=builder /app/relay/target/release/risc0-xmr-relay ./relay

EXPOSE 8080
CMD ["./relay"]