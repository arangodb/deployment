#!/bin/bash
parted /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd mklabel msdos
parted -s /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd mkpart primary "linux-swap(v1)" "0%" "20%"
mkswap /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part1
mkfs -t ext4 /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part2
