# --------------------------------------------------
# 1. Builder stage: clone & compile Cryo
# --------------------------------------------------
FROM debian:bullseye-slim AS builder

# Required packages for building Cryo
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    build-essential \
    git \
    pkg-config \
    libssl-dev \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy the modular patch system
COPY apply_patches.py /tmp/cryo-patches/apply_patches.py
COPY patches/ /tmp/cryo-patches/patches/

# Clone the repository at the pinned commit
RUN mkdir -p /tmp/cryo-build \
    && cd /tmp/cryo-build \
    && git clone https://github.com/paradigmxyz/cryo.git \
    && cd cryo \
    && git checkout eba6192298e40add4d35d1587511d875f6d770e4

# --------------------------------------------------
# Apply all patches using the modular patch system
# --------------------------------------------------
RUN cd /tmp/cryo-build/cryo \
    && cp -r /tmp/cryo-patches/* . \
    && python3 apply_patches.py

# --------------------------------------------------
# Build Cryo CLI
# --------------------------------------------------
RUN cd /tmp/cryo-build/cryo \
    && echo "=== Starting build ===" \
    && export RUSTFLAGS="-C codegen-units=1 -C opt-level=s -C debuginfo=0" \
    && export CARGO_BUILD_JOBS=1 \
    && export CARGO_NET_RETRY=5 \
    && cd crates/cli \
    && cargo build --release --no-default-features --jobs 1

# --------------------------------------------------
# 2. Runtime stage: base image with Cryo and Python
# --------------------------------------------------
FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gcc \
    g++ \
    python3 \
    python3-pip \
    python3-dev \
    libssl-dev \
    libssl1.1 \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Copy the compiled Cryo binary from builder stage
COPY --from=builder /tmp/cryo-build/cryo/target/release/cryo /usr/local/bin/cryo
RUN chmod +x /usr/local/bin/cryo

# Test Cryo installation
RUN cryo --version \
    && echo "=== Testing column support ===" \
    && cryo help blocks | grep -A 20 "other available columns" || true \
    && echo "=== End of column list ==="

# Add labels for tracking
LABEL org.opencontainers.image.source="https://github.com/gnosischain/cryo-base"
LABEL org.opencontainers.image.description="Base image with pre-compiled Cryo for fast builds"
LABEL cryo.commit="eba6192298e40add4d35d1587511d875f6d770e4-patched"