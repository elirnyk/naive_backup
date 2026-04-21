FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Debian build tools
RUN apt-get update && apt-get install -y 
    devscripts 
    debhelper 
    build-essential 
    git 
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
