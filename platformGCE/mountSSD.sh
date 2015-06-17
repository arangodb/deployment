#!/bin/bash
swapon /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part1
if [ ! -d /data ] ; then
    mkdir /data
fi
mount /dev/disk/by-id/scsi-0Google_EphemeralDisk_local-ssd-part2 /data -t ext4
chown core.core /data
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

