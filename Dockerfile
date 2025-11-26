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
    sed \
    && rm -rf /var/lib/apt/lists/*

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# Add Rust to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Clone the repository first
RUN mkdir -p /tmp/cryo-build && cd /tmp/cryo-build \
    && git clone https://github.com/paradigmxyz/cryo.git \
    && cd cryo \
    && git checkout eba6192298e40add4d35d1587511d875f6d770e4

# Use sed to make the modifications instead of patches (more reliable)
RUN cd /tmp/cryo-build/cryo \
    && echo "=== Original blocks.rs around struct definition ===" \
    && grep -n -A 5 -B 5 "withdrawals_root.*Vec" crates/freeze/src/datasets/blocks.rs \
    && echo "=== Adding withdrawals field ===" \
    && sed -i '/withdrawals_root: Vec<Option<Vec<u8>>>,/a\    withdrawals: Vec<Option<String>>,' crates/freeze/src/datasets/blocks.rs \
    && echo "=== Adding serde_json import ===" \
    && sed -i '/use polars::prelude::\*;/a use serde_json;' crates/freeze/src/datasets/blocks.rs \
    && echo "=== Modified blocks.rs around struct definition ===" \
    && grep -n -A 10 -B 5 "withdrawals_root.*Vec" crates/freeze/src/datasets/blocks.rs \
    && echo "=== Finding process_block function ===" \
    && grep -n "store.*withdrawals_root" crates/freeze/src/datasets/blocks.rs \
    && echo "=== Adding withdrawals processing logic ===" \
    && sed -i '/store!(schema, columns, withdrawals_root, block.withdrawals_root.map(|x| x.0.to_vec()));/a\    if schema.has_column("withdrawals") {\
        let withdrawals_json = block.withdrawals.as_ref().map(|w| {\
            serde_json::to_string(w).unwrap_or_else(|_| "[]".to_string())\
        });\
        columns.withdrawals.push(withdrawals_json);\
    }' crates/freeze/src/datasets/blocks.rs \
    && echo "=== Verifying changes ===" \
    && grep -n -A 8 -B 2 "withdrawals" crates/freeze/src/datasets/blocks.rs

# Patch crates/freeze/src/types/sources.rs to treat RPC errors (like null) as empty traces
# This ensures that if the RPC returns null for traces (which causes a deserialization error or similar),
# it defaults to an empty Vec instead of failing.
RUN cd /tmp/cryo-build/cryo \
    && echo "=== Patching sources.rs to handle null RPC responses as empty ===" \
    && sed -i '/fn trace_replay_block_transactions/,/}/ { \
        /Self::map_err(/,/)/c\        Ok(self.provider.trace_replay_block_transactions(block.into(), \&trace_types).await.unwrap_or(Vec::new())) \
    }' crates/freeze/src/types/sources.rs \
    && echo "=== Verifying sources.rs patch ===" \
    && grep -A 5 "fn trace_replay_block_transactions" crates/freeze/src/types/sources.rs

# Build with verbose output to catch any issues
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

# Install Python and required system dependencies
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

# Create symlinks for python and pip
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Copy the compiled Cryo binary from builder stage
COPY --from=builder /tmp/cryo-build/cryo/target/release/cryo /usr/local/bin/cryo

# Verify binary is executable
RUN chmod +x /usr/local/bin/cryo

# Test Cryo installation and verify withdrawals column
RUN cryo --version \
    && echo "=== Testing withdrawals column support ===" \
    && cryo help blocks | grep -A 20 "other available columns" \
    && echo "=== End of column list ==="

# Add labels for tracking
LABEL org.opencontainers.image.source="https://github.com/gnosischain/cryo-base"
LABEL org.opencontainers.image.description="Base image with pre-compiled Cryo for fast builds"
LABEL cryo.commit="eba6192298e40add4d35d1587511d875f6d770e4-patched-withdrawals-sed"
LABEL cryo.withdrawals="enabled"