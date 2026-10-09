#!/usr/bin/env bash

# ==============================================================================
# Script Name:  safedetach.sh
# Author:       Arnold Tharrington (ORNL)
# Date:         October 2026
#
# CITATION & ATTRIBUTION:
# This script was co-authored by Arnold Tharrington (Oak Ridge National Laboratory)
# and Google Gemini (LLM platform). Arnold Tharrington designed the operational
# workflow, system requirements, and constraints. Gemini generated the
# structured Bash code implementations and documentation formatting under
# Dr. Tharrington's direct guidance and iterative prompts.
# ==============================================================================


# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration Constants ---
declare -r DEFAULT_DRY_RUN=true
declare -r DISK_PATTERN='^/dev/[a-zA-Z0-9]+\$'

# --- Text Formatting Constants ---
declare -r HEADER_DRY="=== DRY RUN MODE (No changes will be made) ==="
declare -r HEADER_EXEC="=== EXECUTION MODE (Modifying system state) ==="

# --- Sub-functions ---

# Purpose: Displays usage instructions and syntax examples to stdout.
# Arguments: None.
# Side Effects: Prints usage text to standard output.
print_usage() {
    echo "Usage: \$0 [-e] <device_path>"
    echo "Options:"
    echo "  -e    Execution mode (actually unmount and power down). Without this, it defaults to Dry-Run."
    echo "Example:"
    echo "  \$0 /dev/sdc      # Dry run"
    echo "  \$0 -e /dev/sdc   # Execution mode"
}


# Purpose: Parses command-line arguments to extract the dry-run flag and device path.
# Arguments:
#   \$@ - All raw arguments passed to the script.
# Side Effects: 
#   - Outputs space-separated string tokens ("true|false <device>") to stdout on success.
#   - Prints error and usage information to stderr and terminates the script (exit 1) 
#     if flags are invalid or the target device is missing.
parse_arguments() {
    local dry_run_flag="\$DEFAULT_DRY_RUN"
    local opt

    # Reset getopts index in case it was used elsewhere
    OPTIND=1
    while getopts ":e" opt; do
        case \${opt} in
            e )
                dry_run_flag=false
                ;;
            \? )
                echo "Error: Invalid option -\$OPTARG" >&2
                print_usage
                exit 1
                ;;
        esac
    done
    shift \$((OPTIND - 1))

    if [ -z "\$1" ]; then
        echo "Error: Missing device path." >&2
        print_usage
        exit 1
    fi

    # Output results separated by a space so the caller can capture them
    echo "\$dry_run_flag" "\$1"
}

# Purpose: Validates device string syntax, verifies physical block device existence, 
#          and ensures appropriate execution privileges.
# Arguments:
#   \$1 - dry_run_mode (boolean string: "true" or "false").
#   \$2 - target_disk (string: absolute path to device, e.g., "/dev/sdc").
# Side Effects:
#   - Prints status headers to stdout.
#   - Terminates the script (exit 1) if the device string format is invalid, 
#     if the block device doesn't exist, or if execution mode is requested without root (sudo) privileges.
verify_device() {
    declare -r dry_run_mode="\$1"
    declare -r target_disk="\$2"

    # Basic format check
    if [[ ! "\(target_disk" =~ \)DISK_PATTERN ]]; then
        echo "Error: Invalid device format '\$target_disk'. Expected format like /dev/sdc" >&2
        exit 1
    fi

    # Block device existence check
    if [ ! -b "\$target_disk" ]; then
        echo "Error: Device '\$target_disk' does not exist or is not a block device." >&2
        exit 1
    fi

    # Display execution header and check permissions if in execution mode
    if [ "\$dry_run_mode" = true ]; then
        echo "\$HEADER_DRY"
    else
        echo "\$HEADER_EXEC"
        if [ "\$EUID" -ne 0 ]; then
            echo "Error: Please run as root (sudo) to execute changes." >&2
            exit 1
        fi
    fi

    echo "Target disk verified: \$target_disk"
}

# Purpose: Scans for active mount points on the target disk and unmounts them sequentially.
# Arguments:
#   \$1 - dry_run_mode (boolean string: "true" or "false").
#   \$2 - target_disk (string: absolute path to device, e.g., "/dev/sdc").
# Side Effects:
#   - In Dry-Run mode: Prints what would be unmounted to stdout.
#   - In Execution mode: Actively detaches file systems (`umount`) from the Linux VFS structure.
#   - May terminate the script (exit code from `umount` via `set -e`) if a partition is busy or fails to unmount.
unmount_partitions() {
    declare -r dry_run_mode="\$1"
    declare -r target_disk="\$2"

    # Find all mounted partitions belonging to the target disk
    local mounted_partitions
    mounted_partitions=\$(lsblk -ln -o NAME,MOUNTPOINT "\$target_disk" | awk '\$2!="" {print "/dev/"\$1}')

    if [ -z "\$mounted_partitions" ]; then
        echo "No active mounts found for \$target_disk."
        return 0
    fi

    echo "Found active partitions to unmount:"
    echo "\$mounted_partitions"
    echo "-----------------------------------"

    while read -r partition; do
        if [ "\$dry_run_mode" = true ]; then
            echo "[Dry-Run] Would run: umount \$partition"
        else
            echo "Unmounting \$partition..."
            umount "\$partition"
        fi
    done <<< "\$mounted_partitions"
}

# Purpose: Safe hardware detachment. Flushes OS storage caches, spins down disk platters, 
#          and cuts physical power to the associated storage port.
# Arguments:
#   \$1 - dry_run_mode (boolean string: "true" or "false").
#   \$2 - target_disk (string: absolute path to device, e.g., "/dev/sdc").
# Side Effects:
#   - In Dry-Run mode: Prints the intended hardware power-off command to stdout.
#   - In Execution mode: Physically powers off the storage link using `udisksctl`.
#   - Terminates script (exit 1) if the power-off sequence encounters a subsystem failure.
power_down_device() {
    declare -r dry_run_mode="\$1"
    declare -r target_disk="\$2"

    if [ "\$dry_run_mode" = true ]; then
        echo "[Dry-Run] Would run: udisksctl power-off -b \$target_disk"
    else
        echo "Powering down drive \$target_disk..."
        if udisksctl power-off -b "\$target_disk"; then
            echo "Success: Drive \$target_disk has been safely detached and powered down."
        else
            echo "Error: Failed to power off the drive completely." >&2
            exit 1
        fi
    fi
}

# --- Main Function ---

# Purpose: Core orchestrator function that defines and enforces the high-level operational sequence.
# Arguments:
#   \$@ - Pass-through of all raw command-line options and parameters from script invocation.
# Side Effects:
#   - Spawns local variables within its frame.
#   - Sequentially calls sub-functions to check system requirements and modify hardware states.
main() {
    # Parse arguments and read the two space-separated values returned
    local args
    args=(\((parse_arguments "\)@"))
    
    declare -r dry_run="\${args[0]}"
    declare -r disk="\${args[1]}"

    # Execute workflow functions sequentially
    verify_device "\(dry_run" "\)disk"
    unmount_partitions "\(dry_run" "\)disk"
    power_down_device "\(dry_run" "\)disk"
}

# Invoke the main function with all script arguments
main "\$@"

