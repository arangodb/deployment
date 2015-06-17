#!/bin/bash
swapon /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part1
mount /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part2 /data -t ext4
chown core.core /data
