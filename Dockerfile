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
    && rm -rf /var/lib/apt/lists/*

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y
# Add Rust to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Clone the repository with specific commit
RUN mkdir -p /tmp/cryo-build && cd /tmp/cryo-build \
    && git clone https://github.com/paradigmxyz/cryo.git \
    && cd cryo \
    # Checkout the specific commit (avoid missing field `creationMethod` due to alloy)
    && git checkout eba6192298e40add4d35d1587511d875f6d770e4 \
    # Configure minimal memory usage
    && export RUSTFLAGS="-C codegen-units=1 -C opt-level=s -C debuginfo=0" \
    && export CARGO_BUILD_JOBS=1 \
    && export CARGO_NET_RETRY=5 \
    && cd crates/cli \
    # Build binary with minimal features
    && cargo build --release --no-default-features --jobs 1

# --------------------------------------------------
# 2. Runtime stage: base image with Cryo and Python
# --------------------------------------------------
FROM debian:bullseye-slim

# Install Python and required system dependencies including libssl
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

# Create a symlink for python3 to be accessible as python
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Copy the compiled Cryo binary from builder stage
COPY --from=builder /tmp/cryo-build/cryo/target/release/cryo /usr/local/bin/cryo

# Verify binary is executable
RUN chmod +x /usr/local/bin/cryo

# Test Cryo installation to verify libssl1.1 is properly linked
RUN ldd /usr/local/bin/cryo && \
    cryo --version || echo "Cryo installation needs troubleshooting"

# Add labels for tracking
LABEL org.opencontainers.image.source="https://github.com/gnosischain/cryo-base"
LABEL org.opencontainers.image.description="Base image with pre-compiled Cryo for fast builds"
LABEL cryo.commit="eba6192298e40add4d35d1587511d875f6d770e4"