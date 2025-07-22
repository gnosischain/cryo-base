# Cryo Base Image

This repository contains the base Docker image with pre-compiled Cryo binary for fast application builds.

## Purpose

Building Cryo from source takes several hours, especially for ARM64 architecture. This base image is built weekly (or on-demand) and contains:

- Pre-compiled Cryo binary (specific commit: `eba6192298e40add4d35d1587511d875f6d770e4`)
- Python 3 runtime
- All necessary system dependencies (libssl, gcc, g++)

## Usage

In your application's Dockerfile:

```dockerfile
FROM ghcr.io/gnosischain/cryo-base:latest

# Your application code here
WORKDIR /app
COPY . .
# ...
```

One can run this version as

```shell
 docker run --rm -v "$(pwd)":/data cryo-base:latest \
  cryo blocks \
  --blocks 39828831:39828831 \
  --rpc 'URL' \
  --include-columns block_number timestamp withdrawals_root withdrawals \
  -o /data
```
## Build Schedule

- **Automatic builds**: Every Sunday at 2 AM UTC
- **Manual builds**: On push to main branch or via workflow dispatch

## Manual Build

To trigger a manual build with a specific Cryo commit:

1. Go to Actions → "Build Cryo Base Image"
2. Click "Run workflow"
3. Optionally specify a Cryo commit hash
4. Click "Run workflow"

## Versioning

- `latest`: Always points to the most recent build
- `YYYYMMDD`: Date-based tags for specific versions

## Architecture Support

- linux/amd64
- linux/arm64

Both architectures are built in parallel for faster builds.

## Update Process

When Cryo releases a new version:

1. Update the commit hash in `Dockerfile`
2. Push to main branch or trigger manual build
3. Wait for build completion (usually 2-3 hours)
4. Update your application to use the new base image

## Contents

The base image includes:

- Debian bullseye-slim base
- Cryo binary at `/usr/local/bin/cryo`
- Python 3.x with pip
- Build essentials (gcc, g++)
- OpenSSL libraries
- CA certificates