#!/bin/bash
# m3u8dump.sh – HLS m3u8 downloader v2.1 (modularized)
# Contributors: 0x8616 (dw5) & f81337 (do76) & 4ida (aidabyte)
#
# Usage:
#   ./m3u8dump.sh "https://test-streams.mux.dev/pts_shift/master.m3u8" 1 "https://referer.from.website" "Mozilla/5.0 (PotatOS 5.1) InternetExploder/0.1"
#
# Note:
#   This script is experimental and may not work in all cases.
#   It has known issues with m3u8 files that have URL parameters, non‑standard naming, etc.
# wget edition

##############################
# Helper function: safe download a file using wget
download_file() {
    local url="$1"
    local output_file="$2"
    # --no-clobber prevents overwriting an existing file.
    wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "$url" -O "$output_file"
}

##############################
# Function: download a m3u8 playlist and then process (download) its segments.
# Arguments:
#   $1 – The m3u8 path (could be relative or absolute)
#   $2 – The base URL for relative paths (usually derived from the master URL)
download_m3u8() {
    local playlist="$1"
    local base_url="$2"
    local playlist_file

    # Determine if the playlist URL is absolute or relative.
    if [[ "$playlist" =~ ^https?:// ]]; then
        playlist_file=$(basename "$playlist")
        download_file "$playlist" "$playlist_file"
    else
        playlist_file="$playlist"
        download_file "${base_url}/${playlist}" "$playlist_file"
    fi

    # Process the segments inside the playlist:
    # Remove comment lines, carriage returns and duplicates.
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

        # Download the segment (using its basename as output name)
        if [[ "$segment" =~ ^https?:// ]]; then
            download_file "$segment" "$(basename "$segment")"
        else
            download_file "${base_url}/${segment}" "$segment"
        fi
    done
}

##############################
# Main function: m3u8dump
# Parameters:
#   $1 – URL of the master m3u8 playlist
#   $2 – (Optional) logging flag (set to 1 to enable logging of URLs in job_LINKS.txt)
#   $3 – (Optional) referer header (default: "https://stream.nty")
#   $4 – (Optional) user-agent string (default: a Firefox UA)
m3u8dump() {
    local master_m3u8="$1"
    logfile="${2:-0}"
    referer="${3:-https://stream.nty}"
    cuseragent="${4:-Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0}"

    # Derive the base URL (stream_m3u8) by stripping "/master.m3u8" from the provided URL.
    # Note: This simple approach may not work if your m3u8 file is named differently.
    stream_m3u8=$(echo "$master_m3u8" | sed 's|/master.m3u8$||')

    # If the master file already exists, ask whether to delete it.
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

    # Clear the job_LINKS.txt log file (if it exists)
    rm -f job_LINKS.txt

    # [1] Download the master playlist
    download_file "$master_m3u8" "master.m3u8"

    # [2] Process variant playlists listed in the master playlist.
    # Extract non-comment lines, remove duplicates, sort.
    local variants
    variants=$(grep -v '^#' master.m3u8 | tr -d '\r' | awk '!arr[$0]++' | sort | uniq)
    echo "-------------------"
    echo "Processing variant playlists..."
    for variant in $variants; do
        # Check that the variant appears to be a m3u8 playlist.
        if [[ ! "$variant" =~ \.m3u8$ ]]; then
            echo "Warning: '$variant' does not end with .m3u8 – skipping."
            continue
        fi
        # Log the variant URL if logging is enabled.
        if [ "$logfile" -eq 1 ]; then
            if [[ "$variant" =~ ^https?:// ]]; then
                echo "$variant" >> job_LINKS.txt
            else
                echo "${stream_m3u8}/${variant}" >> job_LINKS.txt
            fi
        fi
        # Download the variant playlist and its segments.
        download_m3u8 "$variant" "$stream_m3u8"
    done

    # [3] Process audio (or i-frame) playlists embedded in the master playlist.
    # They are identified by a pattern like: ,URI="something.m3u8"
    local audio_tags
    audio_tags=$(grep -o ',URI="[^"]*\.m3u8"' master.m3u8 | grep -Po '(?<=URI=")[^"]*\.m3u8' | awk '!arr[$0]++' | sort | uniq)
    if [ -n "$audio_tags" ]; then
        echo "-------------------"
        echo "Processing audio playlists..."
        for audio in $audio_tags; do
            # Log the audio URL if logging is enabled.
            if [ "$logfile" -eq 1 ]; then
                echo "${stream_m3u8}/${audio}" >> job_LINKS.txt
            fi
            # Download the audio playlist.
            download_file "${stream_m3u8}/${audio}" "$audio"
            # Then, process any variant playlists within the audio m3u8.
            local audio_variants
            audio_variants=$(grep -v '^#' "$audio" | tr -d '\r' | awk '!arr[$0]++' | sort | uniq)
            for variant in $audio_variants; do
                if [[ ! "$variant" =~ \.m3u8$ ]]; then
                    echo "Warning: '$variant' (from audio playlist) does not end with .m3u8 – skipping."
                    continue
                fi
                if [ "$logfile" -eq 1 ]; then
                    echo "${stream_m3u8}/${variant}" >> job_LINKS.txt
                fi
                download_m3u8 "$variant" "$stream_m3u8"
            done
        done
    fi

    echo "==== THE END. ===="
}

##############################
# If the script is run directly, call m3u8dump with the command-line arguments.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <master.m3u8 URL> [logflag] [referer] [useragent]"
        echo "Example: $0 \"https://test-streams.mux.dev/pts_shift/master.m3u8\" 1 \"https://referer.from.website\" \"Mozilla/5.0 (Your User Agent)\""
        exit 1
    fi
    m3u8dump "$@"
fi
