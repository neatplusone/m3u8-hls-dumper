<#
.SYNOPSIS
    A simple HLS M3U8 dumper (PowerShell version)

.DESCRIPTION
    Downloads a master.m3u8, finds variant playlists, downloads them,
    and then downloads all segments. Also attempts to handle audio
    or i-frame playlists found in the master.

.PARAMETER init_m3u8
    The master.m3u8 URL.

.PARAMETER logfile
    Whether to log URLs into job_LINKS.txt (use "1" for logging, "0" for no logging).

.PARAMETER referer
    Referer to supply in HTTP headers.

.PARAMETER cuseragent
    User-Agent to supply in HTTP headers.

.EXAMPLE
    PS> .\m3u8dump.ps1 "https://test-streams.mux.dev/pts_shift/master.m3u8" 1 "https://referer.from.website" "Mozilla/5.0 (PotatOS 5.1) InternetExploder/0.1"

#>

param(
    [Parameter(Mandatory = $true)]
    [string] $init_m3u8,

    [string] $logfile = "0",

    [string] $referer = "https://vanillo.tv",

    [string] $cuseragent = "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0"
)

Write-Host "m3u8 hls PowerShell dumper | Based on original Bash script v2.0.1a"
Write-Host "Usage example:"
Write-Host "  .\\m3u8dump.ps1 `"https://test-streams.mux.dev/pts_shift/master.m3u8`" 1 `"https://referer.from.website`" `"CustomUserAgentHere`""
Write-Host "=================================================================="
Write-Host "Note: This is not a perfect dumper; see original disclaimers."

# If no init_m3u8 is provided (shouldn't happen if we make it Mandatory, but just in case):
if (-not $init_m3u8) {
    Write-Host "`nPlease provide a master.m3u8 URL as a command line argument."
    Write-Host "Example: .\\m3u8dump.ps1 `"https://test-streams.mux.dev/pts_shift/master.m3u8`" 1"
    Write-Host "==== THIS DUMPER IS NOT 100% PERFECT ===="
    exit 1
}

# Remove "/master.m3u8" from the end of the URL to get the base (stream_m3u8).
# e.g. https://example.com/folder/master.m3u8 -> https://example.com/folder
$stream_m3u8 = $init_m3u8 -replace "/master\.m3u8$",""

# Check if master.m3u8 exists locally and possibly remove it
if (Test-Path -Path "master.m3u8") {
    Write-Host "`nThe file 'master.m3u8' already exists."
    Write-Host "It's possible other files linked to that m3u8 are downloaded too."
    $answer = Read-Host "Do you want to delete master.m3u8? (yes/no)"
    if ($answer -match "^(y|yes)$") {
        Write-Host "Deleting 'master.m3u8'..."
        Remove-Item "master.m3u8" -Force
    }
    else {
        Write-Host "Skipping file deletion."
    }
}

# Clear old job_LINKS.txt if it exists
if (Test-Path -Path "job_LINKS.txt") {
    Remove-Item "job_LINKS.txt" -Force
}

# Helper function to download a URL to a specified OutFile using custom headers
function Download-Url {
    param(
        [string]$url,
        [string]$outfile
    )
    # -Headers allows us to specify Referer and User-Agent
    # --no-clobber approach: We'll skip download if the outfile already exists (by default).
    if (-not (Test-Path $outfile)) {
        try {
            Invoke-WebRequest -Uri $url `
                              -Headers @{ "Referer" = $referer; "User-Agent" = $cuseragent } `
                              -OutFile $outfile -UseBasicParsing -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to download $url: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "File '$outfile' already exists; skipping."
    }
}


#
# 1) Download the master playlist
#
Write-Host "`nDownloading master.m3u8..."
Download-Url -url $init_m3u8 -outfile "master.m3u8"

#
# 2) Parse the master playlist to get the variant playlist URLs
#    ignoring lines that start with '#' or empty lines
#
Write-Host "`nParsing 'master.m3u8' to find variant playlists..."
$variantPlaylists = Get-Content -Path "master.m3u8" `
    | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne "" } `
    | Select-Object -Unique
    # If you want them alphabetically sorted, you can append: | Sort-Object

Write-Host "Found variant playlists:"
$variantPlaylists | ForEach-Object { Write-Host "  $_" }
Write-Host "-------------------"

# Download each variant playlist and then its associated segments
foreach ($variant in $variantPlaylists) {

    # If logfile=1, append to job_LINKS.txt
    if ($logfile -eq "1") {
        "$($stream_m3u8)/$variant" | Out-File -FilePath "job_LINKS.txt" -Append
    }

    # Figure out where to download from. If it starts with http(s)://, use it directly.
    # Otherwise, prepend $stream_m3u8.
    if ($variant -match '^https?://') {
        $variantUrl = $variant
        # The output file name can be just the last portion of the URL, e.g. everything after the last slash
        $outfileName = [System.IO.Path]::GetFileName($variant)
    }
    else {
        $variantUrl = "$stream_m3u8/$variant"
        $outfileName = $variant
    }

    Write-Host "`nDownloading variant playlist: $variantUrl -> $outfileName"
    Download-Url -url $variantUrl -outfile $outfileName

    # Now parse that variant playlist for segments
    if (Test-Path -Path $outfileName) {
        $segmentUrls = Get-Content -Path $outfileName `
            | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne "" } `
            | Select-Object -Unique
            # | Sort-Object if you want them sorted

        foreach ($segment in $segmentUrls) {
            Write-Host "  Segment: $segment"

            if ($logfile -eq "1") {
                "$($stream_m3u8)/$segment" | Out-File -FilePath "job_LINKS.txt" -Append
            }

            if ($segment -match '^https?://') {
                $segmentUrl = $segment
                $segmentName = [System.IO.Path]::GetFileName($segment)
            }
            else {
                $segmentUrl = "$stream_m3u8/$segment"
                $segmentName = $segment
            }

            Download-Url -url $segmentUrl -outfile $segmentName
        }
    }
}


#
# 3) Extract audio/i-frame playlist URLs (any lines containing URI="something.m3u8")
#
Write-Host "`nAUDIO, IFRAMES, ETC URI="
# We'll use regex to capture the content inside URI="...m3u8"
# e.g. URI="audio-variant.m3u8"
# We only want the inside portion: audio-variant.m3u8
#
$audioTags = Select-String -Path "master.m3u8" -Pattern 'URI="([^"]*\.m3u8)"' -AllMatches `
    | ForEach-Object { $_.Matches } `
    | ForEach-Object { $_.Groups[1].Value } `
    | Select-Object -Unique

foreach ($audio in $audioTags) {
    Write-Host "  $audio"

    if ($logfile -eq "1") {
        "$($stream_m3u8)/$audio" | Out-File -FilePath "job_LINKS.txt" -Append
    }

    # Download the audio or i-frame .m3u8
    $audioUrl = "$stream_m3u8/$audio"
    Download-Url -url $audioUrl -outfile $audio

    # Once downloaded, parse for segments
    if (Test-Path -Path $audio) {
        $subPlaylists = Get-Content -Path $audio `
            | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne "" } `
            | Select-Object -Unique

        foreach ($variant2 in $subPlaylists) {
            Write-Host "    Audio/i-frame sub-playlist: $variant2"

            if ($logfile -eq "1") {
                "$($stream_m3u8)/$variant2" | Out-File -FilePath "job_LINKS.txt" -Append
            }

            if ($variant2 -match '^https?://') {
                $variantUrl2 = $variant2
                $outfileName2 = [System.IO.Path]::GetFileName($variant2)
            }
            else {
                $variantUrl2 = "$stream_m3u8/$variant2"
                $outfileName2 = $variant2
            }

            Download-Url -url $variantUrl2 -outfile $outfileName2

            # Segments for this sub-playlist
            if (Test-Path -Path $outfileName2) {
                $segmentUrls2 = Get-Content -Path $outfileName2 `
                    | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne "" } `
                    | Select-Object -Unique

                foreach ($segment2 in $segmentUrls2) {
                    Write-Host "      Segment: $segment2"

                    if ($logfile -eq "1") {
                        "$($stream_m3u8)/$segment2" | Out-File -FilePath "job_LINKS.txt" -Append
                    }

                    if ($segment2 -match '^https?://') {
                        $segmentUrl2 = $segment2
                        $segmentFile2 = [System.IO.Path]::GetFileName($segment2)
                    }
                    else {
                        $segmentUrl2 = "$stream_m3u8/$segment2"
                        $segmentFile2 = $segment2
                    }

                    Download-Url -url $segmentUrl2 -outfile $segmentFile2
                }
            }
        }
    }
}

Write-Host "`n==== THE END. ===="

