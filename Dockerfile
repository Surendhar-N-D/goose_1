# syntax=docker/dockerfile:1.4
# goose CLI and Server Docker Image
# Multi-stage build for minimal final image size

# Build stage
FROM rust:1.82-bookworm AS builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    pkg-config \
    libssl-dev \
    libdbus-1-dev \
    libclang-dev \
    protobuf-compiler \
    libprotobuf-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /build

# Copy source code
COPY . .

# Build release binaries with optimizations
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
ENV CARGO_PROFILE_RELEASE_LTO=true
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
ENV CARGO_PROFILE_RELEASE_OPT_LEVEL=z
ENV CARGO_PROFILE_RELEASE_STRIP=true
RUN cargo build --release --package goose-cli

# Runtime stage - minimal Debian
# Base image digest bumped to bust the GHA layer cache on the apt-get layer below,
# which otherwise keeps serving the libssl3 fetched at first build (see CVE-2026-31789,
# fixed in Debian bookworm-security as libssl3 3.0.20-1~deb12u2).
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

# Install only runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libdbus-1-3 \
    libgomp1 \
    libxcb1 \
    curl \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /build/target/release/goose /usr/local/bin/goose

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash goose && \
    mkdir -p /home/goose/.config/goose && \
    chown -R goose:goose /home/goose

# Set up environment
ENV PATH="/usr/local/bin:${PATH}"
ENV HOME="/home/goose"

# Switch to non-root user
USER goose
WORKDIR /home/goose

# Default to goose CLI
ENTRYPOINT ["/usr/local/bin/goose"]
CMD ["--help"]

# Labels for metadata
LABEL org.opencontainers.image.title="goose"
LABEL org.opencontainers.image.description="goose CLI"
LABEL org.opencontainers.image.vendor="AAIF"
LABEL org.opencontainers.image.source="https://github.com/aaif-goose/goose"
