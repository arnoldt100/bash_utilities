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

# --- Global Variables ---

SCRIPT_MODE=""
declare -r USAGE_MODE="usage_mode"
declare -r PROCESSING_MODE="processing_mode"

# --- FUNCTIONS ---

# ==========================================
# PURPOSE:    Display script usage instructions and exit.
# ARGUMENTS:  None
# SIDE EFFECTS: Prints help text to terminal screen and exits the entire 
#              script execution environment with an exit code of 0.
# ==========================================
usage() {
    echo "Usage: $0 --path /path/to/directory [--profile secure-shared|strict-private|public-shared] [--dry-run]" | tee /dev/tty
    echo "       $0 -h | --help" | tee /dev/tty
    echo "" | tee /dev/tty
    echo "Options:" | tee /dev/tty
    echo "  -h, --help              : Display this help message and exit" | tee /dev/tty
    echo "  --path <dir>            : Target directory to modify recursively" | tee /dev/tty
    echo "  --profile <name>        : Permission strategy profile to enforce" | tee /dev/tty
    echo "  -d, --dry-run           : Preview permission changes without applying them" | tee /dev/tty
    echo "" | tee /dev/tty
    echo "Profiles:" | tee /dev/tty
    echo "  secure-shared (Default) : Dirs 750, Files 640 | Best for internal teams" | tee /dev/tty
    echo "  strict-private          : Dirs 700, Files 600 | Only you can access" | tee /dev/tty
    echo "  public-shared           : Dirs 755, Files 644 | Standard for public web servers" | tee /dev/tty
    exit 0
}

# ==========================================
# PURPOSE:    Parse command-line arguments to extract target configurations.
# ARGUMENTS:  $@ (All positional arguments passed down from main)
# SIDE EFFECTS: - Triggers usage() and exits 0 if help is requested or no args provided.
#               - Prints error text to stderr and exits with status 1 on failure.
#               - Outputs a pipe-delimited string to stdout on success.
# ==========================================
parse_arguments() {
    # Default values scoped inside parser
    local target_dir=""
    local profile="secure-shared"
    local dry_run="false"

    if [[ "$#" -eq 0 ]]; then
        SCRIPT_MODE=${USAGE_MODE}
        usage

    fi

    # Quick lookahead scan for help flags to prevent any accidental path execution
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            SCRIPT_MODE=${USAGE_MODE}
            usage
        fi
    done

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            --path)
                target_dir="$2"
                shift 2
                ;;
            --profile)
                profile="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                echo "Use -h or --help for instructions." >&2
                exit 1
                ;;
        esac
    done

    # Ensure the path variable is not empty
    if [[ -z "$target_dir" ]]; then
        echo "Error: Missing required option --path" >&2
        echo "Use -h or --help for instructions." >&2
        exit 1
    fi

    # Output parameters back to main function using a clean delimiter
    echo "$target_dir|$profile|$dry_run"
}

# ==========================================
# PURPOSE:    Validate that the directory path exists and the profile is recognized.
# ARGUMENTS:  $1 - Target directory path string
#             $2 - Profile configuration string
# SIDE EFFECTS: Prints errors to stderr and terminates the script with exit status 1 
#               if validation fails. Does nothing if configuration is safe.
# ==========================================
validate_inputs() {
    local target_dir="$1"
    local profile="$2"

    # Check directory
    if [[ ! -d "$target_dir" ]]; then
        echo "Error: Target directory '$target_dir' does not exist or is not a directory." >&2
        exit 1
    fi

    # Check profile mapping validity
    case "$profile" in
        secure-shared|strict-private|public-shared)
            # Profile is valid
            ;;
        *)
            echo "Error: Invalid profile '$profile'." >&2
            echo "Valid profiles: secure-shared, strict-private, public-shared" >&2
            exit 1
            ;;
    esac
}

# ==========================================
# PURPOSE:    Execute permission changes via chmod or display simulated outputs.
# ARGUMENTS:  $1 - Target directory path string
#             $2 - Profile configuration string
#             $3 - Dry-run toggle flag ("true" or "false")
# SIDE EFFECTS: - When dry-run is true: Prints structural simulation previews to stdout.
#               - When dry-run is false: Actively alters filesystem file modes and bits 
#                 recursively on the targeted directory and files.
# ==========================================
apply_permissions() {
    local target_dir="$1"
    local profile="$2"
    local dry_run="$3"
    
    local dir_perms=""
    local file_perms=""

    # Map the selected profile to octal permissions
    case "$profile" in
        strict-private)
            dir_perms="700"
            file_perms="600"
            ;;
        public-shared)
            dir_perms="755"
            file_perms="644"
            ;;
        secure-shared|*)
            dir_perms="750"
            file_perms="640"
            ;;
    esac

    if [[ "$dry_run" == "true" ]]; then
        echo "=== DRY RUN MODE: No changes will be saved ==="
        echo "Profile selected: $profile"
        echo ""
        
        echo "Would set the following directories to $dir_perms:"
        find "$target_dir" -type d -printf "  [DIR]  %p -> $dir_perms\n"
        
        echo ""
        echo "Would set the following files to $file_perms:"
        find "$target_dir" -type f -printf "  [FILE] %p -> $file_perms\n"
        
        echo ""
        echo "=== End of Dry Run Preview ==="
    else
        echo "Using profile: $profile"
        echo "Applying permissions to target: $target_dir"

        # Set directories
        echo "Setting directories to $dir_perms..."
        find "$target_dir" -type d -exec chmod "$dir_perms" {} +

        # Set files
        echo "Setting files to $file_perms..."
        find "$target_dir" -type f -exec chmod "$file_perms" {} +

        echo "Permissions successfully updated!"
    fi
}

# ==========================================
# PURPOSE:    Core script orchestrator. Collects parameters from subroutines,
#             manages data bridging via IFS pipelines, and triggers actions.
# ARGUMENTS:  $@ (All terminal command line positional flags passed to the execution environment)
# SIDE EFFECTS: Spawns internal subshells for data parsing. Terminates execution if any 
#               downstream function returns an error exit code.
# ==========================================
main() {
    # Use declare to explicitly enforce variable types safely inside main scope
    declare parsed_data
    parsed_data=$(parse_arguments "$@") || exit 1

    declare target_dir
    declare profile
    declare dry_run

    # Extract clean local fields using standard IFS parsing

    IFS='|' read -r target_dir profile dry_run <<< "$parsed_data"

    case "${SCRIPT_MODE}" in
      ${PROCESSING_MODE})
          validate_inputs "$target_dir" "$profile"
          apply_permissions "$target_dir" "$profile" "$dry_run"
          ;;

      ${USAGE_MODE})
          # In usage mode. Do nothing and exit.
          ;;
    esac
}

# --- EXECUTION ENTRY POINT ---
main "$@"

