#!/bin/bash
# ==============================================================================
# log-archive-lisandradp85.sh
# Author  : lisandradp85
# Purpose : Compress a log directory into a timestamped .tar.gz archive,
#           store it in a destination folder, and record the operation.
#
# Usage   : ./log-archive-lisandradp85.sh <log-dir> [dest-dir] [--clean]
#
# Options :
#   <log-dir>    Directory whose contents will be archived (required).
#   [dest-dir]   Where to save the archive (optional; default: ./archives).
#   --clean      Delete the original log directory after a successful archive.
# ==============================================================================

# ── Exit immediately on unset variables ──────────────────────────────────────
set -u

# ── Constants ─────────────────────────────────────────────────────────────────
readonly SCRIPT_NAME=$(basename "$0")
readonly RETENTION_DAYS=7          # Archives older than this will be removed

# ── print_usage ───────────────────────────────────────────────────────────────
# Shows help text and exits with code 1.
print_usage() {
    echo "Usage: $SCRIPT_NAME <log-dir> [dest-dir] [--clean]"
    echo ""
    echo "  <log-dir>   Path to the directory containing logs to archive (required)."
    echo "  [dest-dir]  Destination folder for the .tar.gz file (default: ./archives)."
    echo "  --clean     Remove the original log directory after archiving."
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME /var/log"
    echo "  $SCRIPT_NAME /var/log /mnt/backups"
    echo "  $SCRIPT_NAME /var/log /mnt/backups --clean"
    exit 1
}

# ── die ───────────────────────────────────────────────────────────────────────
# Prints an error message to stderr and exits with the given code.
die() {
    local message="$1"
    local exit_code="${2:-1}"
    echo "ERROR: $message" >&2
    exit "$exit_code"
}

# ── parse_arguments ───────────────────────────────────────────────────────────
# Reads positional parameters and sets the global variables:
#   input_dir, output_dir, purge_source.
parse_arguments() {
    if [ $# -lt 1 ]; then
        print_usage
    fi

    input_dir="$1"
    output_dir="${2:-./archives}"
    purge_source=false

    # Accept --clean as third argument
    if [ "${3:-}" = "--clean" ]; then
        purge_source=true
    fi
}

# ── validate_inputs ───────────────────────────────────────────────────────────
# Ensures the source directory exists and is readable.
validate_inputs() {
    if [ ! -d "$input_dir" ]; then
        die "'$input_dir' does not exist or is not a directory." 2
    fi

    if [ ! -r "$input_dir" ]; then
        die "No read permission on '$input_dir'." 3
    fi
}

# ── get_dir_size ──────────────────────────────────────────────────────────────
# Returns a human-readable size of the given path (e.g. "4.2M").
get_dir_size() {
    local target_path="$1"
    du -sh "$target_path" 2>/dev/null | cut -f1
}

# ── apply_retention_policy ────────────────────────────────────────────────────
# Deletes .tar.gz archives older than RETENTION_DAYS from the destination.
apply_retention_policy() {
    echo "Applying retention policy: removing archives older than ${RETENTION_DAYS} days..."
    local removed
    removed=$(find "$output_dir" -maxdepth 1 -name "logs_archive_*.tar.gz" \
              -mtime +"$RETENTION_DAYS" -print -delete 2>/dev/null)

    if [ -n "$removed" ]; then
        echo "Removed old archives:"
        echo "$removed"
    else
        echo "No archives exceeded the retention limit."
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    parse_arguments "$@"
    validate_inputs

    # ── Header ────────────────────────────────────────────────────────────────
    echo "=============================================="
    echo "  LOG ARCHIVE TOOL  |  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  User : $(whoami)"
    echo "=============================================="
    echo ""

    # ── Size before compression ───────────────────────────────────────────────
    space_before=$(get_dir_size "$input_dir")
    echo "Source directory : $input_dir"
    echo "Size before      : ${space_before:-N/A}"
    echo ""

    # ── Prepare destination directory ─────────────────────────────────────────
    mkdir -p "$output_dir" || die "Could not create destination directory '$output_dir'." 4

    # ── Build archive filename with timestamp ─────────────────────────────────
    snapshot_time=$(date +%Y%m%d_%H%M%S)
    archive_filename="logs_archive_${snapshot_time}.tar.gz"
    archive_file="${output_dir}/${archive_filename}"

    # ── Compress ──────────────────────────────────────────────────────────────
    echo "Compressing '$input_dir' → '$archive_file' ..."
    tar -czf "$archive_file" -C "$(dirname "$input_dir")" "$(basename "$input_dir")"

    if [ $? -ne 0 ]; then
        die "Compression failed. The archive may be incomplete." 5
    fi

    echo "Compression successful."
    echo ""

    # ── Size after compression ────────────────────────────────────────────────
    space_after=$(get_dir_size "$archive_file")
    echo "Archive size     : ${space_after:-N/A}"
    echo ""

    # ── Log the operation ─────────────────────────────────────────────────────
    activity_log="${output_dir}/archive_log.txt"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | source=$input_dir | archive=$archive_filename | before=${space_before:-N/A} | after=${space_after:-N/A}" >> "$activity_log"
    echo "Activity logged  : $activity_log"

    # ── Retention policy ──────────────────────────────────────────────────────
    echo ""
    apply_retention_policy

    # ── Auto-clean ────────────────────────────────────────────────────────────
    if [ "$purge_source" = true ]; then
        echo ""
        echo "WARNING: --clean flag is set."
        read -rp "Delete '$input_dir' permanently? (yes/no): " confirmation
        if [ "$confirmation" = "yes" ]; then
            rm -rf "$input_dir"
            echo "Source directory '$input_dir' has been removed."
        else
            echo "Deletion cancelled. Source directory was kept."
        fi
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    echo "=============================================="
    echo "  DONE  |  Archive: $archive_filename"
    echo "=============================================="
}

main "$@"
