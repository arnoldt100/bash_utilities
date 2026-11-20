#! /usr/bin/env bash
echo "=== LSBLK ==="
lsblk -f -o NAME,FSTYPE,SIZE,UUID,MOUNTPOINT
echo -e "\n=== BLKID ===" 
sudo blkid
echo -e "\n=== FSTAB ==="
cat /etc/fstab 
echo -e "\n=== DF ==="
df -hT
