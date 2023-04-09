#!/bin/bash
#test
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
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "$init_m3u8" -O master.m3u8

# Parse the master playlist to get the variant playlist URLs
variant_playlists=$(sed '/^#/d; s/\r//g' master.m3u8)

# Download each variant playlist and its associated segments
for variant_playlist in $variant_playlists; do
  echo "$variant_playlist"

  # Download the variant playlist and its associated segments
  curl --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer "$referer" -OJ "${stream_m3u8}/${variant_playlist}"

  # Extract the segment URLs from the variant playlist and download them
  segment_urls=$(sed '/^#/d; s/\r//g' "${variant_playlist}")
  for segment_url in $segment_urls; do
    echo "$segment_url"
    curl --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer "$referer" -OJ "${stream_m3u8}/${segment_url}"
  done
done

# Extract the audio and i-frame playlist URLs
audio_tags=$(grep -o ',URI="[^"]*\.m3u8"'  master.m3u8 | sed 's/,URI="//; s/"//; s/\r//g')
# audio and iframe

# Download each audio playlist and its associated segments
for audio in $audio_tags; do
  echo "$audio"
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${stream_m3u8}/${audio}" -O "${audio}"
Parse the audio playlist to get the segment URLs

audio_segment_urls=$(grep -v '^#' "${audio}"| tr -d '\r')
# Download each audio segment

for audio_segment_url in $audio_segment_urls; do
echo $audio_segment_urls
wget --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0" --referer="$referer" "${cdn_host}${audio_segment_url}" -O "${audio_segment_url}"
done
done
# Download each iframe playlist and its associated segments


echo "All files downloaded successfully!"
