#!/bin/bash

# Set the image size (256MB) and image name
OUTPUT_IMG=aapen.img
OUTPUT_IMG_SIZE=256
MOUNT_POINT="$(mktemp -d)"

# Step 1: Create an empty disk image of 256mB
dd if=/dev/zero of=${OUTPUT_IMG} bs=1M count=${OUTPUT_IMG_SIZE}

# Step 2: Attach the image as a loop device
DISK_DEVICE=$(hdiutil attach -nomount $OUTPUT_IMG | grep "/dev/disk" | awk '{print $1}')

if [ -z "$DISK_DEVICE" ]; then
  echo "Failed to attach the disk image."
  exit 1
fi

echo "Disk image attached as $DISK_DEVICE"

# Step 3: Create an MBR partition table with fdisk
echo "Partitioning the disk with fdisk..."
(
echo "y"         # Yes, initialize MBR
echo "edit 1"    # Edit partition 1
echo "0b"        # Set FAT32 as partition type
echo "n"         # Not using CHS parameters
echo "63"        # Starting sector
echo "524097"    # Ending sector
echo "write"     # Write the partition table
echo "quit"      # Exit fdisk
) | fdisk -ie $DISK_DEVICE

# Step 4: Format the partition as FAT32
PARTITION="${DISK_DEVICE}s1"
echo "Formatting the partition ${PARTITION} as FAT32..."
newfs_msdos -F 32 $PARTITION

# Step 5: Mount the partition
mkdir -p ${MOUNT_POINT}
mount -t msdos ${PARTITION} ${MOUNT_POINT}

# Step 5: Recursively copy files from `firmware` and `sdfiles` into
# the root of that partition. Copy kernel binaries from `build`
cp -r firmware/* ${MOUNT_POINT}/
cp -r sdfiles/* ${MOUNT_POINT}/
cp -r build/kernel* ${MOUNT_POINT}/

mkdir -p ${MOUNT_POINT}/src
cp -r src/* ${MOUNT_POINT}/src/

# Delete the resource forks and other macOS crud
(cd ${MOUNT_POINT}; find . -name '._*' | xargs rm; rm -rf .fseventsd)

# Ensure the copy operation completes
sync

# Step 6: Unmount the partition
umount ${PARTITION}

# Step 6: Detach the disk image
#echo "Detaching the disk image..."
hdiutil detach ${DISK_DEVICE}

echo "Disk image $OUTPUT_IMG created successfully with a 256MB FAT32 partition."
