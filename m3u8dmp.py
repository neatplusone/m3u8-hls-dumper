#!/usr/bin/env python3
"""

m3u8dump.py – HLS m3u8 downloader v3.0 (Python version)
Contributors: do76 2025, Converted from the original bash script dw5 2023
(c) 2025 neatplusone

HLS m3u8 downloader – downloads a master m3u8 playlist, variant playlists,
audio playlists and their segments.

DESCRIPTION:
    This script downloads an HLS master playlist and recursively downloads all
    variant and audio playlists as well as their media segments. It supports optional
    logging (saving downloaded URLs to a file) and allows you to customize the
    referer header and user-agent string.

PARAMETERS:
    -url  (Required) URL of the master m3u8 playlist.
    -l    (Optional) Logging flag. Set to 1 to enable logging of URLs in job_LINKS.txt. (Default: 0)
    -ref  (Optional) The referer header to use. (Default: "https://stream.nty")
    -ua   (Optional) The user-agent string to use. (Default: Firefox UA)

EXAMPLE:
    python m3u8dump.py -url "https://test-streams.mux.dev/pts_shift/master.m3u8" -l 1 -ref "https://referer.from.website" -ua "Mozilla/5.0 (PotatOS 5.1) InternetExploder/0.1"
"""

import os
import re
import argparse
import datetime
from urllib.parse import urljoin, urlparse

import requests


def download_file(url, output_file, log_flag, referer, user_agent):
    """Download a file from a URL if it does not already exist."""
    if os.path.exists(output_file):
        print(f"File '{output_file}' already exists, skipping download.")
        return
    print(f"Downloading '{url}' to '{output_file}'...")
    headers = {"Referer": referer, "User-Agent": user_agent}
    try:
        with requests.get(url, headers=headers, stream=True) as response:
            response.raise_for_status()
            with open(output_file, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
    except Exception as e:
        print(f"Error downloading '{url}': {e}")


def download_m3u8(playlist, base_url, log_flag, referer, user_agent):
    """
    Downloads a m3u8 playlist (absolute or relative) and then downloads all
    segments listed within it. Only processes the file further if it ends with .m3u8.
    """
    # Determine if the playlist URL is absolute or relative.
    if playlist.startswith("http://") or playlist.startswith("https://"):
        playlist_url = playlist
        playlist_file = os.path.basename(urlparse(playlist).path)
    else:
        playlist_url = urljoin(base_url + "/", playlist)
        playlist_file = playlist

    # Download the file.
    download_file(playlist_url, playlist_file, log_flag, referer, user_agent)

    # Only process the file as a playlist if it ends with .m3u8.
    if not playlist_file.endswith(".m3u8"):
        # Not a playlist file; assume it's a media segment and return.
        return

    # Process and download each segment listed in the playlist.
    if os.path.exists(playlist_file):
        # Use errors='replace' to handle any unexpected encoding issues.
        with open(playlist_file, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
        segments = sorted(set(line.strip() for line in lines if not line.startswith("#") and line.strip()))
        for segment in segments:
            # Determine segment URL (absolute vs. relative)
            if segment.startswith("http://") or segment.startswith("https://"):
                segment_url = segment
                output_segment = os.path.basename(urlparse(segment).path)
            else:
                segment_url = urljoin(base_url + "/", segment)
                output_segment = segment

            # Log the segment URL if logging is enabled.
            if log_flag:
                with open("job_LINKS.txt", "a", encoding="utf-8") as log_file:
                    log_file.write(segment_url + "\n")
            download_file(segment_url, output_segment, log_flag, referer, user_agent)
    else:
        print(f"Playlist file '{playlist_file}' not found.")


def m3u8_dump(master_url, log_flag, referer, user_agent):
    """Main function to download the master playlist, variants, and audio playlists."""
    # Create an output folder named with the current date/time.
    output_dir = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    os.makedirs(output_dir, exist_ok=True)
    os.chdir(output_dir)
    print(f"Created and changed directory to {output_dir}")

    # Derive the base URL by removing "/master.m3u8" from the master URL.
    if master_url.endswith("/master.m3u8"):
        base_url = master_url[:-len("/master.m3u8")]
    else:
        parsed_url = urlparse(master_url)
        base_url = f"{parsed_url.scheme}://{parsed_url.netloc}{os.path.dirname(parsed_url.path)}"

    # If master.m3u8 already exists, ask whether to delete it.
    if os.path.exists("master.m3u8"):
        print("The file 'master.m3u8' already exists.")
        answer = input("Do you want to delete it? (yes/no) ")
        if answer.lower() in ['y', 'yes']:
            print("Deleting 'master.m3u8'...")
            os.remove("master.m3u8")
        else:
            print("Skipping deletion.")

    # Remove job_LINKS.txt if it exists.
    if os.path.exists("job_LINKS.txt"):
        os.remove("job_LINKS.txt")

    # Download the master playlist.
    download_file(master_url, "master.m3u8", log_flag, referer, user_agent)

    # Process variant playlists found in the master playlist.
    print("-------------------")
    print("Processing variant playlists...")
    if not os.path.exists("master.m3u8"):
        print("Master playlist file 'master.m3u8' not found.")
        return

    with open("master.m3u8", 'r', encoding='utf-8') as f:
        lines = f.readlines()

    variants = sorted(set(line.strip() for line in lines if not line.startswith("#") and line.strip()))
    for variant in variants:
        if not (variant.endswith(".m3u8") or variant.endswith(".mp4")):
            print(f"Warning: '{variant}' does not end with .m3u8 or .mp4 – skipping.")
            continue
        # Log variant URL if logging is enabled.
        if log_flag:
            if variant.startswith("http://") or variant.startswith("https://"):
                log_variant = variant
            else:
                log_variant = urljoin(base_url + "/", variant)
            with open("job_LINKS.txt", "a", encoding="utf-8") as log_file:
                log_file.write(log_variant + "\n")
        download_m3u8(variant, base_url, log_flag, referer, user_agent)

    # Process embedded audio (or i-frame) playlists from the master playlist.
    with open("master.m3u8", 'r', encoding='utf-8') as f:
        master_content = f.read()
    audio_matches = re.findall(r'URI="([^"]*\.m3u8)"', master_content)
    audio_tags = sorted(set(audio_matches))
    if audio_tags:
        print("-------------------")
        print("Processing audio playlists...")
        for audio in audio_tags:
            audio_url = urljoin(base_url + "/", audio)
            if log_flag:
                with open("job_LINKS.txt", "a", encoding="utf-8") as log_file:
                    log_file.write(audio_url + "\n")
            download_file(audio_url, audio, log_flag, referer, user_agent)
            if os.path.exists(audio):
                with open(audio, 'r', encoding='utf-8') as af:
                    audio_lines = af.readlines()
                audio_variants = sorted(set(line.strip() for line in audio_lines if not line.startswith("#") and line.strip()))
                for variant in audio_variants:
                    if not (variant.endswith(".m3u8") or variant.endswith(".mp4")):
                        print(f"Warning: '{variant}' (from audio playlist) does not end with .m3u8 or .mp4 – skipping.")
                        continue
                    if log_flag:
                        with open("job_LINKS.txt", "a", encoding="utf-8") as log_file:
                            log_file.write(urljoin(base_url + "/", variant) + "\n")
                    download_m3u8(variant, base_url, log_flag, referer, user_agent)
            else:
                print(f"Error: Audio playlist file '{audio}' not found.")
    print(f"==== THE END. Files saved in directory: {output_dir} ====")


def main():
    parser = argparse.ArgumentParser(
        description="HLS m3u8 downloader – downloads a master m3u8 playlist, variant playlists, audio playlists and their segments."
    )
    parser.add_argument("-url", "--master_url", required=True, help="URL of the master m3u8 playlist.")
    parser.add_argument("-l", "--log_flag", type=int, default=0,
                        help="Logging flag. Set to 1 to enable logging of URLs in job_LINKS.txt. (Default: 0)")
    parser.add_argument("-ref", "--referer", default="https://stream.internal",
                        help="The referer header to use. (Default: https://stream.internal)")
    parser.add_argument("-ua", "--user_agent", default="Mozilla/5.0 (X11; Linux x86_64; rv:136.0) Gecko/20100101 Firefox/136.0",
                        help="The user-agent string to use. (Default: Firefox UA)")
    args = parser.parse_args()
    m3u8_dump(args.master_url, args.log_flag, args.referer, args.user_agent)


if __name__ == '__main__':
    main()
