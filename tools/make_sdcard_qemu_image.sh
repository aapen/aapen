#! /bin/bash

OUTPUT_IMG=aapen.img
OUTPUT_IMG_SIZE=256
MOUNT_POINT="$(mktemp -d)"

# Step 1: Create an empty disk image of 256MB
dd if=/dev/zero of=${OUTPUT_IMG} bs=1M count=${OUTPUT_IMG_SIZE}

# Step 2: Use sfdisk to create a partition table with one FAT32
# partition with all available space
echo ',,b,*' | sfdisk ${OUTPUT_IMG}

# Setup loop device
LOOP_DEVICE=$(sudo losetup -fP --show ${OUTPUT_IMG})

# Wait a bit to ensure the loop device is properly set up
sleep 2

# The first partition usually ends up being /dev/loop0p1 or similar
PARTITION="${LOOP_DEVICE}p1"

# Step 3: Use mkfs.fat to format the first partition
sudo mkfs.fat -F 32 ${PARTITION}

# Step 4: Mount the partition
mkdir -p ${MOUNT_POINT}
sudo mount -o user,uid=$(id -u),gid=$(id -g) ${PARTITION} ${MOUNT_POINT}

# Step 5: Recursively copy files from `firmware` and `sdfiles` into
# the root of that partition. Copy kernel binaries from `build`
cp -r firmware/* ${MOUNT_POINT}/
cp -r sdfiles/* ${MOUNT_POINT}/
cp -r build/kernel* ${MOUNT_POINT}/

mkdir -p ${MOUNT_POINT}/src
cp -r src/* ${MOUNT_POINT}/src/

# Ensure the copy operation completes
sync

# Step 6: Unmount the partition
sudo umount ${MOUNT_POINT}

# Detach the loop device
sudo losetup -d ${LOOP_DEVICE}

# Remove the temp directory
rmdir ${MOUNT_POINT}

echo "Disk image creation and preparation completed successfully."
