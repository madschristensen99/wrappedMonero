FROM rust:1.89 as builder

WORKDIR /app/fhe-engine
COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN apt-get update && apt-get install -y pkg-config libssl-dev
RUN cargo build --release

FROM rust:1.89

RUN apt-get update && apt-get install -y pkg-config libssl-dev

WORKDIR /app
COPY --from=builder /app/fhe-engine/target/release/fhe-policy-engine ./fhe-engine

EXPOSE 8081
CMD ["./fhe-engine"]