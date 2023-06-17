FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt update && \
    apt install -y qemu-system-arm gdb-multiarch device-tree-compiler

RUN wget -O /tmp/zig.tar.xz https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3664+0f5aff344.tar.xz && \
    cd /opt && tar xf /tmp/zig.tar.xz && \
    ln -sf /opt/zig-linux-x86_64-0.11.0-dev.3664+0f5aff344 /opt/zig

COPY zigpath.sh /etc/profile.d/10-zigpath.sh