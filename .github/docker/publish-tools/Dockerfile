# --- Stage 1: Builder ---
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    pkg-config \
    libjson-c-dev \
    liblua5.1-0-dev \
    && rm -rf /var/lib/apt/lists/*

# Build libubox
RUN git clone --depth 1 https://github.com/openwrt/libubox.git /tmp/libubox && \
    cd /tmp/libubox && \
    mkdir build && cd build && \
    cmake .. -DBUILD_EXAMPLES=OFF && \
    make install

# Build usign
RUN git clone --depth 1 https://github.com/openwrt/usign.git /tmp/usign && \
    cd /tmp/usign && \
    mkdir build && cd build && \
    cmake .. && \
    make install

# --- Stage 2: Runtime ---
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies
# apt-utils provides apt-ftparchive
RUN apt-get update && apt-get install -y \
    gpg \
    apt-utils \
    curl \
    ca-certificates \
    xxd \
    gh \
    gzip \
    git \
    libjson-c12 \
    liblua5.1-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy binaries and libraries from builder
COPY --from=builder /usr/local/bin/usign /usr/local/bin/usign
COPY --from=builder /usr/local/lib/libubox.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libblobmsg_json.so* /usr/local/lib/

# Refresh ldconfig for the new libraries
RUN ldconfig

# Set default working directory
WORKDIR /workspace