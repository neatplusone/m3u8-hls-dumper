#!/bin/bash

if [ $# -eq 0 ]
  then
    echo "Please provide a CDN host master.m3u8 URL as a command line argument."
    exit 1
fi

init_m3u8=$1
stream_m3u8=$(echo "$1" | sed 's|/master.m3u8$||')

# Set the referer and CDN host
referer="https://go3.lt"
cdn_host="https://stream.go3.lt"

# Download the master playlist
wget --no-clobber --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "$init_m3u8" -O master.m3u8

# Parse the master playlist to get the variant playlist URLs
variant_playlists=$(grep -v '^#' master.m3u8 | tr -d '\r')

# Download each variant playlist and its associated segments
for variant_playlist in $variant_playlists; do
echo $variant_playlists
    # Download the variant playlist
    wget --no-clobber --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${stream_m3u8}/${variant_playlist}" -O "${variant_playlist}"

    # Parse the variant playlist to get the segment URLs
    segment_urls=$(grep -v '^#' "${variant_playlist}"| tr -d '\r')

    # Download each segment
    for segment_url in $segment_urls; do
	echo $segment_urls
        wget --no-clobber --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${stream_m3u8}/${segment_url}" -O "${segment_url}"
    done
done

# GLITCHY BOY
echo EXTRAS

# Extract the audio and i-frame playlist URLs
audio_tags=$(grep -o ',URI="[^"]*\.m3u8"'  master.m3u8 | tr -d '\r' | grep -Po '(?<=URI=")[^"]*\.m3u8')
iframe_tags=$(grep -o ',URI="[^"]*\.m3u8"'  master.m3u8 | tr -d '\r' | grep -Po '(?<=URI=")[^"]*\.m3u8')

# Loop through each audio tag and echo it
for audio in $audio_tags; do
  echo "$audio"
  wget --no-clobber --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${stream_m3u8}/${audio}" -O "${audio}"

# Parse the master playlist to get the variant playlist URLs
variant_playlists=$(grep -v '^#' "$audio" | tr -d '\r')

# Download each variant playlist and its associated segments
for variant_playlist in $variant_playlists; do
echo $variant_playlists
    # Download the variant playlist
    wget --no-clobber --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${stream_m3u8}/${variant_playlist}" -O "${variant_playlist}"

    # Parse the variant playlist to get the segment URLs
    segment_urls=$(grep -v '^#' "${variant_playlist}"| tr -d '\r')

    # Download each segment
    for segment_url in $segment_urls; do
	echo $segment_urls
        wget --no-clobber --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${stream_m3u8}/${segment_url}" -O "${segment_url}"
    done
done


done


echo THE END.
