#!/bin/bash
# m3u8dump.sh | m3u8 hls bash dumper 2.0.1a | 0x8616 (dw5) & f81337 (do76) & 4ida (aidabyte)

if [ $# -eq 0 ]
  then
    echo "Please provide a master.m3u8 URL as a command line argument."
    echo "m3u8dump.sh \"https://test-streams.mux.dev/pts_shift/master.m3u8\" 1 \"https://referer.from.website\" \"Mozilla/5.0 (PotatOS 5.1) InternetExploder/0.1\""
    echo "================= THIS DUMPER IS NOT 100% PERFECT ================= "
    echo "WONT WORK WITH: Where there is URL parameters after m3u8?token=1234, folder+m3u8 url_2/vid.m3u8, multiple m3u8 using same exact name for different v/a file, one vid.m3u8 for HD and another vid.m3u8 for 144p"
    echo "Might have problems if .m3u8 name is other than master.m3u8 also"
    echo "Cleanup might be needed for segment files which do have URL parameters (edit code and add --trust-server-names ..?)"
    exit 1
fi

init_m3u8=$1
stream_m3u8=$(echo "$1" | sed 's|/master.m3u8$||')

# !! YOUR CONFIG !!
#output url for each m3u8 and media file
# Set the referer and CDN host
if [[ -n "$3" && -n "$4" ]]; then
    referer=$3
    cuseragent=$4
else
    referer="https://stream.nty"
    cuseragent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0"
fi

if [[ -n "$2" ]]; then
logfile=$2
else
logfile=0
fi
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

rm job_LINKS.txt #clear history
wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "$init_m3u8" -O master.m3u8

# [2] Parse the master playlist to get the variant playlist URLs
#variant_playlists=$(grep -v '^#' master.m3u8 | tr -d '\r'| sort | uniq)
variant_playlists=$(grep -v '^#' master.m3u8 | tr -d '\r'| awk '!arr[$0]++'| sort | uniq)
#echo $variant_playlists
echo "-------------------"

# Download each variant playlist and its associated segments
for variant_playlist in $variant_playlists; do
echo "$variant_playlist"
if [ "$logfile" -eq 1 ]; then
echo "${stream_m3u8}/$variant_playlist">>job_LINKS.txt
fi

if [[ ! $variant_playlist =~ .*\.m3u8$ ]]; then
    echo "Does not end with 'm3u8'. Program will fail. Please contribute if you're a developer. Exiting the program."
    exit 1
fi

# Download the variant playlist
if [[ $variant_playlist == http://* || $variant_playlist == https://* ]]; then
  echo "The variant playlist starts with 'http://' or 'https://.'."
  wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${variant_playlist}" -O "${variant_playlist}"
else
  wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${variant_playlist}" -O "${variant_playlist}"
fi

    # Parse the variant playlist to get the segment URLs
    segment_urls=$(grep -v '^#' "${variant_playlist}"| tr -d '\r'| awk '!arr[$0]++'| sort | uniq)

    # Download each segment
    for segment_url in $segment_urls; do
	echo $segment_url
	if [ "$logfile" -eq 1 ]; then
	echo "${stream_m3u8}/$segment_url">>job_LINKS.txt
	fi

        # Download the variant segment
        if [[ $segment_url == http://* || $segment_url == https://* ]]; then
          echo "The variant playlist starts with 'http://' or 'https://.'."
          wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${segment_url}" -O "${segment_url}"
        else
          wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${segment_url}" -O "${segment_url}"
        fi

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
  if [ "$logfile" -eq 1 ]; then
  echo "${stream_m3u8}/$audio">>job_LINKS.txt
  fi
  wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${audio}" -O "${audio}"

# Parse the master playlist to get the variant playlist URLs
variant_playlists=$(grep -v '^#' "$audio" | tr -d '\r'| awk '!arr[$0]++'| sort | uniq)

if [[ ! $variant_playlist =~ .*\.m3u8$ ]]; then
    echo "Does not end with 'm3u8'. Program will fail. Please contribute if you're a developer. Exiting the program."
    exit 1
fi

# Download each variant playlist and its associated segments
      for variant_playlist in $variant_playlists; do
        echo $variant_playlist
        if [ "$logfile" -eq 1 ]; then
        echo "${stream_m3u8}/$variant_playlist">>job_LINKS.txt
        fi

        # Download the variant playlist
        if [[ $variant_playlist == http://* || $variant_playlist == https://* ]]; then
          echo "The variant playlist starts with 'http://' or 'https://.'."
          wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${variant_playlist}" -O "${variant_playlist}"
        else
          wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${variant_playlist}" -O "${variant_playlist}"
        fi

        # Parse the variant playlist to get the segment URLs
        segment_urls=$(grep -v '^#' "${variant_playlist}"| tr -d '\r'| awk '!arr[$0]++'| sort | uniq)

        # Download each segment
          for segment_url in $segment_urls; do
                echo $segment_url
                if [ "$logfile" -eq 1 ]; then
                echo "${stream_m3u8}/$segment_url">>job_LINKS.txt
                fi

                # Download the variant segment
                if [[ $segment_url == http://* || $segment_url == https://* ]]; then
                  echo "The variant playlist starts with 'http://' or 'https://.'."
                  wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${segment_url}" -O "${segment_url}"
                else
                  wget --no-clobber --user-agent="$cuseragent" --referer="$referer" "${stream_m3u8}/${segment_url}" -O "${segment_url}"
                fi
          done
      done
done


echo "==== THE END. ===="
