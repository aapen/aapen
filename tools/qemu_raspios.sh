#! /bin/bash
#
# See https://interrupt.memfault.com/blog/emulating-raspberry-pi-in-qemu

docker run -it --rm -p 2222:2222 --security-opt seccomp=unconfined stawiski/qemu-raspberrypi-3b:2023-05-03-raspios-bullseye-arm64