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
    lua5.1 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Build libubox
RUN git clone --depth 1 https://github.com/openwrt/libubox.git /tmp/libubox && \
    cd /tmp/libubox && \
    mkdir build && cd build && \
    cmake .. -DBUILD_EXAMPLES=OFF -DLUAPATH=/usr && \
    make install && \
    ldconfig

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
RUN apt-get update && apt-get install -y \
    gpg \
    apt-utils \
    curl \
    ca-certificates \
    xxd \
    gzip \
    git \
    libjson-c5 \
    liblua5.1-0 \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (gh) manually since it's not in default repos
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Copy binaries and libraries from builder
COPY --from=builder /usr/local/bin/usign /usr/local/bin/usign
COPY --from=builder /usr/local/lib/libubox.so* /usr/local/lib/
COPY --from=builder /usr/local/lib/libblobmsg_json.so* /usr/local/lib/

# Refresh ldconfig for the new libraries
RUN ldconfig

# Set default working directory
WORKDIR /workspace