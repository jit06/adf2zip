#!/usr/bin/env bash

# ==============================================================================
# adf2zip
# Extracts content from multiple ADFs (or ZIPs containing ADFs)
# from local paths or URLs, decompresses any nested .lha files,
# and repackages everything into a single flat ZIP file.
# ==============================================================================

#set -euo pipefail

# --- Default values ---
OUTPUT_DIR="$(pwd)"
INPUT_SOURCES=()

# --- Usage function ---
usage() {
	echo "Usage: $(basename "$0") [OPTIONS] <input_file_or_pattern>..."
	echo ""
	echo "Options:"
	echo "	-o, --output-dir	Specify the destination directory for the final ZIP file."
	echo "	-h, --help		Show this help message and exit."
	echo ""
	echo "Arguments:"
	echo "	Input files can be text files containing a list of local paths or HTTP links"
	echo "	(one per line), pointing to ADF files or ZIP files containing an ADF."
	echo ""
	echo "Example:"
	echo "	$(basename "$0") -o my_folder wordworth.list"
	exit 1
}


# --- Dependency check ---
check_dependencies() {
    local deps=("zip" "unzip" "lha" "unadf" "curl")
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}" >&2
        exit 1
    fi
}

# --- Parse command line arguments ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output-dir)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: Option '$1' requires an argument." >&2
                    exit 1
                fi
                mkdir -p "$2"
                OUTPUT_DIR="$(cd "$2" && pwd)"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                usage
                exit 1
                ;;
            *)
                INPUT_SOURCES+=("$1")
                shift
                ;;
        esac
    done

    if [ ${#INPUT_SOURCES[@]} -eq 0 ]; then
        echo "Error: No input source provided." >&2
        usage
        exit 1
    fi
}

# --- Main logic ---
main() {
    check_dependencies
    parse_args "$@"

    # Process each input source provided (supports wildcards/multiple files)
    for src in "${INPUT_SOURCES[@]}"; do
        if [ ! -f "$src" ]; then
            echo "Warning: Input file '$src' not found. Skipping." >&2
            continue
        fi

        # Determine final zip name from the input list filename
        local base_name
        base_name=$(basename "$src" | sed 's/\.[^.]*$//')
        local final_zip="${OUTPUT_DIR}/${base_name}.zip"

        echo "Processing list: $src"

        # Create global temporary workspace
        local tmp_workspace
        tmp_workspace=$(mktemp -d /tmp/adf2zip_workspace_XXXXXX)
        local extract_dir="${tmp_workspace}/extracted_content"
        mkdir -p "$extract_dir"

        # Read the input file line by line
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Trim whitespace
            line=$(echo "$line" | xargs)
            [ -z "$line" ] && continue # Skip empty lines
            [[ "$line" =~ ^# ]] && continue # Skip comments

            local adf_path=""
            local current_tmp=""
            current_tmp=$(mktemp -d /tmp/adf2zip_item_XXXXXX)

            # Check if source is a URL or Local file
            if [[ "$line" =~ ^https?:// ]]; then
                echo "Downloading: $line"
                local download_name
                download_name=$(basename "$line")
                curl --retry 3 --retry-delay 1 -sLfA "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$line" -o "${current_tmp}/${download_name}"
                adf_path="${current_tmp}/${download_name}"
            else
                if [ -f "$line" ]; then
                    adf_path="$line"
                else
                    echo "Warning: File '$line' defined in the list does not exist. Skipping." >&2
                    rm -rf "$current_tmp"
                    continue
                fi
            fi

            # Handle ZIP enclosing an ADF
            if [[ "$adf_path" =~ \.zip$ ]]; then
                echo "Unzipping ADF container: $(basename "$adf_path")"
                local unzip_tmp="${current_tmp}/unzipped"
                mkdir -p "$unzip_tmp"
                unzip -q -o "$adf_path" -d "$unzip_tmp"
                
                # Find the extracted ADF inside
                local found_adf
                found_adf=$(find "$unzip_tmp" -type f -iname "*.adf" -print -quit)
                if [ -n "$found_adf" ]; then
                    adf_path="$found_adf"
                else
                    echo "Warning: No .adf file found inside ZIP ($line). Skipping." >&2
                    rm -rf "$current_tmp"
                    continue
                fi
            fi

            # Extract ADF Content
            if [ -f "$adf_path" ] && [[ "$adf_path" =~ \.adf$ ]]; then
                echo "Extracting ADF: $(basename "$adf_path")"
                # unadf requires the destination to exist, extracts relative paths
                (cd "$extract_dir" && unadf -d "." "$adf_path" &>/dev/null || true)
            else
                echo "Warning: Target '$line' is not a valid ADF or ZIP containing ADF. Skipping." >&2
            fi

            # Cleanup item temporary folder
            rm -rf "$current_tmp"

        done < "$src"

       # Process nested LHA archives inside the global extracted directory
        echo "Checking for nested .lha files..."
        local lha_found=true
        while [ "$lha_found" = true ]; do
            lha_found=false
            # Find all .lha files recursively
            while IFS= read -r -d '' lha_file; do
                lha_found=true
                local lha_dir
                lha_dir=$(dirname "$lha_file")
                
                # Get the archive name without the .lha extension
                local lha_base
                lha_base=$(basename "$lha_file" | sed 's/\.[^.]*$//')

                # Create the dedicated target directory
                local target_dir="${lha_dir}/${lha_base}"
                mkdir -p "$target_dir"

                echo "Extracting nested LHA: $(basename "$lha_file") into ${lha_base}/"
                # Extract LHA content directly into the target directory using -w option
                lha x -w="$target_dir" "$lha_file" &>/dev/null
                
                # Delete the LHA archive after successful extraction
                rm -f "$lha_file"
            done < <(find "$extract_dir" -type f -iname "*.lha" -print0)
        done

        # Process multi-part files (.part1, .part2, etc.) across different directories
        echo "Checking for split part files..."
        # Find all .part1 files recursively
        while IFS= read -r -d '' part1_file; do
            local part1_dir
            part1_dir=$(dirname "$part1_file")
            local part_base
            part_base=$(basename "$part1_file")
            
            # Get the final filename by removing the .part1 extension
            local final_joined_name
            final_joined_name=$(echo "$part_base" | sed 's/\.part1$//')
            local final_joined_path="${part1_dir}/${final_joined_name}"
            
            # Get the base pattern to look for other parts (e.g., "gram.part")
            local part_pattern
            part_pattern=$(echo "$part_base" | sed 's/1$//')
            
            echo "Joining split parts for: $final_joined_name into $part1_dir"
            
            # Find all matching parts, isolate the filename for a clean numerical sort (-V),
            # then reconstruct the full path to feed 'cat'
            find "$extract_dir" -type f -name "${part_pattern}[0-9]*" | \
                awk -F/ '{print $NF, $0}' | \
                sort -V | \
                awk '{print $2}' | \
                xargs cat > "$final_joined_path"
            
            if [ -f "$final_joined_path" ]; then
                # Force the OS to flush write caches and refresh file status
                touch "$final_joined_path"
                sync
                echo "Successfully created joined file: ${final_joined_name} ($(du -sh "$final_joined_path" | awk '{print $1}'))"
            else
                echo "Warning: Failed to join parts for ${part_base}" >&2
            fi
            
        done < <(find "$extract_dir" -type f -name "*.part1" -print0)

        # Generate the final ZIP file
        if [ "$(ls -A "$extract_dir")" ]; then
            echo "Creating final ZIP archive: $final_zip from $extract_dir"
            rm -f "$final_zip"
            (cd "$extract_dir" && zip -q -r "$final_zip" ./*)
            echo "Successfully generated $final_zip"
        else
            echo "Error: No files extracted for $base_name. ZIP was not created." >&2
        fi

        # Cleanup global workspace
        rm -rf "$tmp_workspace"
    done
}

main "$@"