# Multi-stage Dockerfile for Rust Core Backend
FROM rust:latest AS builder
WORKDIR /usr/src/app

# Install build dependencies
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock ./
# Create dummy main to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release --locked
RUN rm -rf src

# Copy real source code
COPY src ./src
RUN touch src/main.rs && cargo build --release --locked

# Runtime image (super small & lightweight)
FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/src/app/target/release/core-backend /app/core-backend

EXPOSE 8000
CMD ["/app/core-backend"]
