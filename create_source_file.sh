#! /usr/bin/env bash

# ==============================================================================
# AUTHOR:       Arnold Tharrington (arnoldt@ornl.gov)
# AFFILIATION:  Oak Ridge National Laboratory (ORNL)
# DESCRIPTION:  Bash script engine to safely generate empty files with strict 
#               umask permissions.
#
# ATTRIBUTION:  This script was co-authored and refactored with the assistance 
#               of a Large Language Model (LLM) AI assistant.
# ==============================================================================

# ==============================================================================
# FUNCTION DEFINITIONS
# ==============================================================================

parse_arguments() {
    # PURPOSE: Parses the command-line arguments to find and validate --filename.
    # ARGUMENTS: Takes all positional arguments passed to the script ($@).
    # SIDE EFFECTS: Echoes the discovered filename string to stdout. Exits the 
    #               entire script with code 1 if parsing fails or option is missing.
    
    local filename=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --filename)
                if [[ -n "$2" && "$2" != -* ]]; then
                    filename="$2"
                    shift 2
                else
                    echo "Error: Argument for --filename is missing." >&2
                    exit 1
                fi
                ;;
            *)
                echo "Error: Unknown option '$1'." >&2
                echo "Usage: $0 --filename <filename>" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "$filename" ]]; then
        echo "Error: --filename option is required." >&2
        echo "Usage: $0 --filename <filename>" >&2
        exit 1
    fi

    echo "$filename"
}

validate_file_absence() {
    # PURPOSE: Ensures the target file does not already exist on disk.
    # ARGUMENTS: $1 - The target file path string to check.
    # SIDE EFFECTS: None if the file is absent. Terminates the entire script 
    #               with exit code 1 if the file already exists.
    
    local target_path="$1"

    if [[ -e "$target_path" ]]; then
        echo "Error: File '$target_path' already exists." >&2
        exit 1
    fi
}

create_empty_file() {
    # PURPOSE: Safely builds an empty file with strict '-rw-rw-r--' (664) permissions.
    # ARGUMENTS: $1 - The target file path string to create.
    # SIDE EFFECTS: Modifies system umask temporarily during execution, writes a 
    #               new empty file to the specified path on disk.
    
    local target_path="$1"
    local old_umask
    
    # Save current umask to avoid permanently altering user environment defaults
    old_umask=$(umask)
    
    # Force 022 mask to guarantee 664 permission logic on creation
    umask 022

    if touch "$target_path"; then
        echo "Success: Created empty file '$target_path' with permissions -rw-r--r--."
        umask "$old_umask"
        return 0
    else
        echo "Error: Failed to create file '$target_path'." >&2
        umask "$old_umask"
        return 1
    fi
}

# ==============================================================================
# MAIN ENGINE EXECUTION
# ==============================================================================

main() {
    # PURPOSE: Orchestrates script execution flow by chaining functions together.
    # ARGUMENTS: Takes all positional arguments passed from the command line ($@).
    # SIDE EFFECTS: Manages the local variable lifecycle and directs system data flow.
    
    local target_file
    
    # Capture the parsed filename locally from the function's stdout output
    target_file=$(parse_arguments "$@") || exit 1

    # Pass the local variable explicitly into subsequent functions
    validate_file_absence "$target_file"
    create_empty_file "$target_file"
}

# Run the script orchestration engine
main "$@"

