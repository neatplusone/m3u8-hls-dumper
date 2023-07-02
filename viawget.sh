#!/bin/bash
# m3u8 hls bash dumper 2.0.1 | 0x8616 (dw5) & f81337 (do76) & 4ida (aidabyte)

if [ $# -eq 0 ]
  then
    echo "Please provide a CDN host master.m3u8 URL as a command line argument."
    exit 1
fi

init_m3u8=$1
stream_m3u8=$(echo "$1" | sed 's|/master.m3u8$||')

init_refer=$2
init_usrag=$3

# !! YOUR CONFIG !!
# Set the referer and CDN host
referer="https://stream.nty"
cuseragent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0"

# [1] Download the master playlist

# Check if the file already exists
if [ -f "master.m3u8" ]; then
    echo "The file master.m3u8 already exists."
    echo "It's possible other files linked to that m3u8 are too, those won't be deleted"
    read -p "Do you want to delete master.m3u8? (yes/no): " answer

    if [[ "$answer" =~ ^[Yy](es)?$ ]]; then
        echo "Deleting 'master.m3u8'..."
        rm "master.m3u8"
    else
        echo "Skipping file deletion."
    fi
fi

echo >job_LINKS.txt #clear history
wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "$init_m3u8" -O master.m3u8

# [2] Parse the master playlist to get the variant playlist URLs
#variant_playlists=$(grep -v '^#' master.m3u8 | tr -d '\r'| sort | uniq)
variant_playlists=$(grep -v '^#' master.m3u8 | tr -d '\r'| awk '!arr[$0]++'| sort | uniq)
echo $variant_playlists
echo "-------------------"

# Download each variant playlist and its associated segments
for variant_playlist in $variant_playlists; do
echo "$variant_playlist"
echo "${stream_m3u8}/$variant_playlist">>job_LINKS.txt
    # Download the variant playlist
    wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${variant_playlist}" -O "${variant_playlist}"

    # Parse the variant playlist to get the segment URLs
    segment_urls=$(grep -v '^#' "${variant_playlist}"| tr -d '\r'| awk '!arr[$0]++'| sort | uniq)

    # Download each segment
    for segment_url in $segment_urls; do
	echo $segment_url
	echo "${stream_m3u8}/$segment_url">>job_LINKS.txt
        wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${segment_url}" -O "${segment_url}"
    done
done

# GLITCHY BOY
echo "AUDIO, IFRAMES, ETC URI="

# [3] Extract the audio and i-frame playlist URLs (URI=)
audio_tags=$(grep -o ',URI="[^"]*\.m3u8"'  master.m3u8 | tr -d '\r' | grep -Po '(?<=URI=")[^"]*\.m3u8'| awk '!arr[$0]++'| sort | uniq)
#iframe_tags=$(grep -o ',URI="[^"]*\.m3u8"'  master.m3u8 | tr -d '\r' | grep -Po '(?<=URI=")[^"]*\.m3u8')

# Loop through each audio tag and echo it
for audio in $audio_tags; do
  echo "$audio"
  echo "${stream_m3u8}/$audio">>job_LINKS.txt
  wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${audio}" -O "${audio}"

# Parse the master playlist to get the variant playlist URLs
variant_playlists=$(grep -v '^#' "$audio" | tr -d '\r'| awk '!arr[$0]++'| sort | uniq)

# Download each variant playlist and its associated segments
      for variant_playlist in $variant_playlists; do
        echo $variant_playlist
        echo "${stream_m3u8}/$variant_playlist">>job_LINKS.txt
        # Download the variant playlist
        wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${variant_playlist}" -O "${variant_playlist}"

        # Parse the variant playlist to get the segment URLs
        segment_urls=$(grep -v '^#' "${variant_playlist}"| tr -d '\r'| awk '!arr[$0]++'| sort | uniq)

        # Download each segment
          for segment_url in $segment_urls; do
            echo $segment_url
            echo "${stream_m3u8}/$segment_url">>job_LINKS.txt
            wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${segment_url}" -O "${segment_url}"
          done
      done
done


echo "==== THE END. ===="
