#!/bin/bash
# m3u8dump.sh – HLS m3u8 downloader v2.2 | wget
# Contributors: 0x8616 (dw5), f81337 (do76), & 4ida (aidabyte)
#
# Usage:
#   ./m3u8dump.sh -url "https://test-streams.mux.dev/pts_shift/master.m3u8" -l 1 -ref "https://referer.from.website" -ua "Mozilla/5.0 (PotatOS 5.1) InternetExploder/0.1"
# Parameters:
#   -url – URL of the master m3u8 playlist
#   -l – (Optional) logging flag (set to 1 to enable logging of URLs in job_LINKS.txt)
#   -ref – (Optional) referer header (default: "https://stream.nty")
#   -ua – (Optional) user-agent string (default: a Firefox UA)
#
# Note:
#   This script is experimental and has known limitations (for instance with m3u8 files that have URL parameters or non‑standard naming).

##############################
# Parse named command-line arguments

# Default values
master_url=""
logfile=0
referer="https://stream.nty"
cuseragent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0"

if [ $# -eq 0 ]; then
    echo "Usage: $0 -url <master.m3u8 URL> [-l <logflag: 1 or 0>] [-ref <referer URL>] [-ua <user-agent string>]"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -url)
            master_url="$2"
            shift; shift
            ;;
        -l)
            logfile="$2"
            shift; shift
            ;;
        -ref)
            referer="$2"
            shift; shift
            ;;
        -ua)
            cuseragent="$2"
            shift; shift
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

if [ -z "$master_url" ]; then
    echo "Error: master URL not provided. Use -url to specify."
    exit 1
fi

##############################
# Helper function: download a file using wget with our options.
download_file() {
    local url="$1"
    local output_file="$2"
    wget -q --show-progress --no-clobber --user-agent="$cuseragent" --referer="$referer" "$url" -O "$output_file"
}

##############################
# Function: download a m3u8 playlist and its segments.
# Arguments:
#   $1 – The m3u8 path (can be relative or absolute)
#   $2 – The base URL for relative paths
download_m3u8() {
    local playlist="$1"
    local base_url="$2"
    local playlist_file

    # Determine whether the playlist URL is absolute or relative.
    if [[ "$playlist" =~ ^https?:// ]]; then
        playlist_file=$(basename "$playlist")
        download_file "$playlist" "$playlist_file"
    else
        playlist_file="$playlist"
        download_file "${base_url}/${playlist}" "$playlist_file"
    fi

    # Process and download each segment in the playlist.
    local segments
    segments=$(grep -v '^#' "$playlist_file" | tr -d '\r' | awk '!arr[$0]++' | sort | uniq)
    for segment in $segments; do
        # Log the segment URL if logging is enabled.
        if [ "$logfile" -eq 1 ]; then
            if [[ "$segment" =~ ^https?:// ]]; then
                echo "$segment" >> job_LINKS.txt
            else
                echo "${base_url}/${segment}" >> job_LINKS.txt
            fi
        fi

        # Download the segment.
        if [[ "$segment" =~ ^https?:// ]]; then
            download_file "$segment" "$(basename "$segment")"
        else
            download_file "${base_url}/${segment}" "$segment"
        fi
    done
}

##############################
# Main function: m3u8dump
# Downloads the master playlist, variant playlists, and embedded audio playlists.
m3u8dump() {
    local master_m3u8="$1"

    # Create an output folder named with the current date/time.
    local output_dir
    output_dir=$(date +"%Y%m%d_%H%M%S")
    mkdir -p "$output_dir"
    cd "$output_dir" || { echo "Failed to change directory to $output_dir"; exit 1; }

    # Derive base URL by stripping "/master.m3u8" from the master URL.
    local stream_m3u8
    stream_m3u8=$(echo "$master_m3u8" | sed 's|/master.m3u8$||')

    # If master.m3u8 already exists, ask whether to delete it.
    if [ -f "master.m3u8" ]; then
        echo "The file 'master.m3u8' already exists."
        read -p "Do you want to delete it? (yes/no): " answer
        if [[ "$answer" =~ ^[Yy](es)?$ ]]; then
            echo "Deleting 'master.m3u8'..."
            rm "master.m3u8"
        else
            echo "Skipping deletion."
        fi
    fi

    rm -f job_LINKS.txt

    # Download the master playlist.
    download_file "$master_m3u8" "master.m3u8"

    # Process variant playlists found in the master playlist.
    local variants
    variants=$(grep -v '^#' master.m3u8 | tr -d '\r' | awk '!arr[$0]++' | sort | uniq)
    echo "-------------------"
    echo "Processing variant playlists..."
    for variant in $variants; do
        if [[ ! "$variant" =~ \.(m3u8|mp4)$ ]]; then
            echo "Warning: '$variant' does not end with .m3u8/.mp4 – skipping."
            continue
        fi
        if [ "$logfile" -eq 1 ]; then
            if [[ "$variant" =~ ^https?:// ]]; then
                echo "$variant" >> job_LINKS.txt
            else
                echo "${stream_m3u8}/${variant}" >> job_LINKS.txt
            fi
        fi
        download_m3u8 "$variant" "$stream_m3u8"
    done

    # Process audio (or i-frame) playlists embedded in the master playlist.
    local audio_tags
    audio_tags=$(grep -o ',URI="[^"]*\.m3u8"' master.m3u8 | grep -Po '(?<=URI=")[^"]*\.m3u8' | awk '!arr[$0]++' | sort | uniq)
    if [ -n "$audio_tags" ]; then
        echo "-------------------"
        echo "Processing audio playlists..."
        for audio in $audio_tags; do
            if [ "$logfile" -eq 1 ]; then
                echo "${stream_m3u8}/${audio}" >> job_LINKS.txt
            fi
            download_file "${stream_m3u8}/${audio}" "$audio"
            local audio_variants
            audio_variants=$(grep -v '^#' "$audio" | tr -d '\r' | awk '!arr[$0]++' | sort | uniq)
            for variant in $audio_variants; do
                if [[ ! "$variant" =~ \.(m3u8|mp4)$ ]]; then
                    echo "Warning: '$variant' (from audio playlist) does not end with .m3u8/.mp4 – skipping."
                    continue
                fi
                if [ "$logfile" -eq 1 ]; then
                    echo "${stream_m3u8}/${variant}" >> job_LINKS.txt
                fi
                download_m3u8 "$variant" "$stream_m3u8"
            done
        done
    fi

    echo "==== THE END. Files saved in directory: $output_dir ===="
}

# Execute the main function with the provided master URL.
m3u8dump "$master_url"
