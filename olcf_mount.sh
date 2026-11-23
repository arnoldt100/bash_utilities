#!/usr/bin/env bash

set -euo pipefail

# Default configuration
HOST="riker.olcf.ornl.gov"
USER_ID="${USER}"
MOUNTPOINT=""
TARGET_DIR=""
UNMOUNT=false

usage() {
    cat <<EOF
Usage:
  Mount:   $(basename "$0") --mountpoint <path> --target <path> [--host <hostname>] [--user <username>]
  Unmount: $(basename "$0") --unmount --mountpoint <path>

Creates or disconnects an SSHFS connection to OLCF systems (default: ${HOST}).
Supports both '--option value' and '--option=value' syntax.

Required arguments (Mount):
  --mountpoint <path>   Local directory where the remote filesystem will be mounted
  --target <path>       Remote directory path on the OLCF host (e.g., /ccs/home/<username>)

Required arguments (Unmount):
  --unmount             Unmount the directory specified by --mountpoint
  --mountpoint <path>   Local directory to unmount

Optional arguments:
  --host <hostname>     OLCF hostname or short name (e.g., riker, frontier, defiant; default: ${HOST})
  --user <username>     OLCF username (defaults to local user: ${USER})
  -h, --help            Show this help message and exit

Examples:
  $(basename "$0") --mountpoint ~/riker_mount --target /ccs/home/jdoe --user jdoe
  $(basename "$0") --mountpoint=~/frontier_mount --target=/lustre/orion/proj123/scratch/jdoe --host=frontier
  $(basename "$0") --unmount --mountpoint ~/riker_mount
EOF
}

# Helper function to extract option values for both '--opt val' and '--opt=val'
extract_arg() {
    if [[ "$1" == *=* ]]; then
        ARG_VAL="${1#*=}"
        SHIFT_COUNT=1
    else
        ARG_VAL="${2:-}"
        SHIFT_COUNT=2
    fi

    if [[ -z "${ARG_VAL}" || "${ARG_VAL:0:1}" == "-" ]]; then
        echo "Error: ${1%%=*} requires a valid non-empty argument." >&2
        exit 1
    fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mountpoint|--mountpoint=*)
            extract_arg "$@"
            MOUNTPOINT="$ARG_VAL"
            shift "$SHIFT_COUNT"
            ;;
        --target|--target=*)
            extract_arg "$@"
            TARGET_DIR="$ARG_VAL"
            shift "$SHIFT_COUNT"
            ;;
        --host|--host=*)
            extract_arg "$@"
            HOST="$ARG_VAL"
            shift "$SHIFT_COUNT"
            ;;
        --user|--user=*)
            extract_arg "$@"
            USER_ID="$ARG_VAL"
            shift "$SHIFT_COUNT"
            ;;
        --unmount)
            UNMOUNT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate mountpoint is provided for both mount and unmount operations
if [[ -z "${MOUNTPOINT}" ]]; then
    echo "Error: --mountpoint is required." >&2
    usage >&2
    exit 1
fi

# Handle unmount workflow
if [[ "${UNMOUNT}" == true ]]; then
    if [[ ! -d "${MOUNTPOINT}" ]]; then
        echo "Error: Mountpoint directory '${MOUNTPOINT}' does not exist." >&2
        exit 1
    fi

    echo "Unmounting ${MOUNTPOINT}..."
    if command -v fusermount &> /dev/null; then
        fusermount -u "${MOUNTPOINT}"
    elif command -v umount &> /dev/null; then
        umount "${MOUNTPOINT}"
    else
        echo "Error: Neither 'fusermount' nor 'umount' was found in your PATH." >&2
        exit 1
    fi

    echo "Successfully unmounted ${MOUNTPOINT}."
    exit 0
fi

# Validate target directory is provided for mount workflow
if [[ -z "${TARGET_DIR}" ]]; then
    echo "Error: --target is required when mounting." >&2
    usage >&2
    exit 1
fi

# Verify sshfs is installed
if ! command -v sshfs &> /dev/null; then
    echo "Error: 'sshfs' is not installed or not in your PATH." >&2
    exit 1
fi

# Create local mountpoint if it does not exist
if [[ ! -d "${MOUNTPOINT}" ]]; then
    echo "Creating local mountpoint directory: ${MOUNTPOINT}"
    mkdir -p "${MOUNTPOINT}"
    chmod 700 "${MOUNTPOINT}"
fi

# Execute SSHFS mount with OLCF-compatible options
echo "Mounting ${USER_ID}@${HOST}:${TARGET_DIR} to ${MOUNTPOINT}..."
echo "Please enter your PIN + RSA SecurID token when prompted."

sshfs "${USER_ID}@${HOST}:${TARGET_DIR}" "${MOUNTPOINT}" \
    -o idmap=user \
    -o ServerAliveInterval=15 \
    -o PreferredAuthentications=keyboard-interactive \
    -o ControlMaster=no

echo "Successfully mounted to ${MOUNTPOINT}."

