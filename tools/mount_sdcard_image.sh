#! /bin/bash

OUTPUT_IMG=aapen.img
MOUNT_POINT="$(mktemp -d)"

# Setup 1: Setup loop device
LOOP_DEVICE=$(sudo losetup -fP --show ${OUTPUT_IMG})

# Wait a bit to ensure the loop device is properly set up
sleep 2

# The first partition usually ends up being /dev/loop0p1 or similar
PARTITION="${LOOP_DEVICE}p1"

# Step 4: Mount the partition
mkdir -p $MOUNT_POINT
sudo mount -o user,uid=$(id -u),gid=$(id -g) $PARTITION $MOUNT_POINT

echo "${OUTPUT_IMG} mounted at ${MOUNT_POINT}, using ${LOOP_DEVICE}"
