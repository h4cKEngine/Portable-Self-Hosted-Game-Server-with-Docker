#!/bin/bash

# Launch with sudo this script in the directory where you want to remove all, for example, from:
# ~/distributed-minecraft-server$ sudo ./utils/delete-all-zone-identifier.sh
# Find and remove all *.Identifier files in the current directory and subdirectories
TARGET_DIR="${1:-.}"

find "$TARGET_DIR" -type f -name "*.Identifier" -exec rm -vf {} +

echo "All *.Identifier files in '$TARGET_DIR' have been removed."
