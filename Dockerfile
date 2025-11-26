# --------------------------------------------------
# 1. Builder stage: clone & compile Cryo
# --------------------------------------------------
FROM debian:bullseye-slim AS builder

# Required packages for building Cryo
# Added python3 for safe patching scripts
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    build-essential \
    git \
    pkg-config \
    libssl-dev \
    python3 \
    sed \
    && rm -rf /var/lib/apt/lists/*

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# Add Rust to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Clone the repository
RUN mkdir -p /tmp/cryo-build && cd /tmp/cryo-build \
    && git clone https://github.com/paradigmxyz/cryo.git \
    && cd cryo \
    && git checkout eba6192298e40add4d35d1587511d875f6d770e4

# --------------------------------------------------
# Patch 1: Withdrawals Support (Original - Untouched)
# --------------------------------------------------
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

# --------------------------------------------------
# Patch 2: Handle Null/Empty Traces from RPC
# --------------------------------------------------
# This script patches the dataset files to catch errors when fetching traces 
# (e.g. if RPC returns null) and default to empty results instead of crashing.
RUN cd /tmp/cryo-build/cryo \
    && echo "import sys, re, os\n\
\n\
# Configuration\n\
trace_files = [\n\
    'crates/freeze/src/multi_datasets/state_diffs.rs',\n\
    'crates/freeze/src/datasets/nonce_diffs.rs',\n\
    'crates/freeze/src/datasets/code_diffs.rs',\n\
    'crates/freeze/src/datasets/balance_diffs.rs',\n\
    'crates/freeze/src/datasets/storage_diffs.rs'\n\
]\n\
vm_file = 'crates/freeze/src/datasets/vm_traces.rs'\n\
\n\
def patch_content(content, is_vm=False):\n\
    # Patch block traces calls: source.trace_block_XXX(...).await?\n\
    pattern = r'(source\.(trace_block_[a-zA-Z_]+)\((.*?)\)\.await)\?'\n\
    \n\
    def replace_block(m):\n\
        full_call = m.group(1)\n\
        if is_vm:\n\
            fallback = '(Some(request.block_number()? as u32), None, vec![])'\n\
        else:\n\
            fallback = '(Some(request.block_number()? as u32), vec![], vec![])'\n\
        return f'match {full_call} {{ Ok(x) => x, Err(_) => {fallback} }}'\n\
\n\
    content = re.sub(pattern, replace_block, content, flags=re.DOTALL)\n\
    \n\
    # Patch transaction traces calls: source.trace_transaction_XXX(...).await\n\
    pattern_tx = r'(source\.(trace_transaction_[a-zA-Z_]+)\((.*?)\)\.await)'\n\
    \n\
    def replace_tx(m):\n\
        full_call = m.group(1)\n\
        if is_vm:\n\
            fallback = '(None, Some(request.transaction_hash()?), vec![])'\n\
        else:\n\
            fallback = '(None, vec![Some(request.transaction_hash()?)], vec![])'\n\
        return f'{full_call}.or_else(|_| Ok({fallback}))'\n\
\n\
    content = re.sub(pattern_tx, replace_tx, content, flags=re.DOTALL)\n\
    return content\n\
\n\
# Process Trace Files\n\
for fpath in trace_files:\n\
    if os.path.exists(fpath):\n\
        with open(fpath, 'r') as f: raw = f.read()\n\
        with open(fpath, 'w') as f: f.write(patch_content(raw, is_vm=False))\n\
        print(f'Patched {fpath}')\n\
\n\
# Process VM File\n\
if os.path.exists(vm_file):\n\
    with open(vm_file, 'r') as f: raw = f.read()\n\
    with open(vm_file, 'w') as f: f.write(patch_content(raw, is_vm=True))\n\
    print(f'Patched {vm_file}')\n\
" > patch_traces.py \
    && python3 patch_traces.py

# Build
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
LABEL cryo.commit="eba6192298e40add4d35d1587511d875f6d770e4-patched-withdrawals-traces"
LABEL cryo.withdrawals="enabled"