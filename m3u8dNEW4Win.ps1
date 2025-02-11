<#
.SYNOPSIS
    HLS m3u8 downloader – downloads a master m3u8 playlist, variant playlists, audio playlists and their segments.

.DESCRIPTION
    This script downloads an HLS master playlist and recursively downloads all variant and audio playlists as well as their
    media segments. It supports optional logging (saving downloaded URLs to a file), and allows you to customize the referer
    header and user-agent string.

.PARAMETER url
    (Required) URL of the master m3u8 playlist.

.PARAMETER l
    (Optional) Logging flag. Set to 1 to enable logging of URLs in job_LINKS.txt. (Default: 0)

.PARAMETER ref
    (Optional) The referer header to use. (Default: "https://stream.nty")

.PARAMETER ua
    (Optional) The user-agent string to use. (Default: Firefox UA)

.EXAMPLE
    .\m3u8dump.ps1 -url "https://test-streams.mux.dev/pts_shift/master.m3u8" -l 1 -ref "https://referer.from.website" -ua "Mozilla/5.0 (PotatOS 5.1) InternetExploder/0.1"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("url")]
    [string]$MasterUrl,

    [Parameter()]
    [Alias("l")]
    [int]$LogFlag = 0,

    [Parameter()]
    [Alias("ref")]
    [string]$Referer = "https://stream.nty",

    [Parameter()]
    [Alias("ua")]
    [string]$UserAgent = "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/114.0"
)

#region Helper Function: Download-File
function Download-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    # Mimic wget --no-clobber: skip download if the file already exists.
    if (Test-Path $OutputFile) {
        Write-Host "File '$OutputFile' already exists, skipping download."
        return
    }

    Write-Host "Downloading '$Url' to '$OutputFile'..."
    try {
        Invoke-WebRequest -Uri $Url `
                          -OutFile $OutputFile `
                          -UserAgent $UserAgent `
                          -Headers @{ "Referer" = $Referer } `
                          -UseBasicParsing
    }
    catch {
        Write-Error "Error downloading '$Url': $_"
    }
}
#endregion

#region Function: Download-M3u8
function Download-M3u8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Playlist,
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )
    
    # Determine if the playlist URL is absolute or relative.
    if ($Playlist -match "^https?://") {
        $PlaylistFile = [System.IO.Path]::GetFileName($Playlist)
        Download-File -Url $Playlist -OutputFile $PlaylistFile
    }
    else {
        $PlaylistFile = $Playlist
        Download-File -Url "$BaseUrl/$Playlist" -OutputFile $PlaylistFile
    }

    # Process and download each segment listed in the playlist.
    if (Test-Path $PlaylistFile) {
        $Segments = Get-Content $PlaylistFile |
                    Where-Object { $_ -notmatch '^#' } |
                    ForEach-Object { $_.Trim() } |
                    Select-Object -Unique |
                    Sort-Object
        foreach ($Segment in $Segments) {
            # Log the segment URL if logging is enabled.
            if ($LogFlag -eq 1) {
                if ($Segment -match "^https?://") {
                    Add-Content -Path "job_LINKS.txt" -Value $Segment
                }
                else {
                    Add-Content -Path "job_LINKS.txt" -Value "$BaseUrl/$Segment"
                }
            }

            # Download the segment.
            if ($Segment -match "^https?://") {
                $OutputSegment = [System.IO.Path]::GetFileName($Segment)
                Download-File -Url $Segment -OutputFile $OutputSegment
            }
            else {
                Download-File -Url "$BaseUrl/$Segment" -OutputFile $Segment
            }
        }
    }
    else {
        Write-Error "Playlist file '$PlaylistFile' not found."
    }
}
#endregion

#region Main Function: M3u8Dump
function M3u8Dump {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MasterM3u8
    )

    # Create an output folder named with the current date/time.
    $outputDir = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Set-Location $outputDir

    # Derive the base URL by removing "/master.m3u8" from the master URL.
    $StreamM3u8 = $MasterM3u8 -replace "/master\.m3u8$", ""

    # If master.m3u8 already exists, ask whether to delete it.
    if (Test-Path "master.m3u8") {
        Write-Host "The file 'master.m3u8' already exists."
        $answer = Read-Host "Do you want to delete it? (yes/no)"
        if ($answer -match "^(y|yes)$") {
            Write-Host "Deleting 'master.m3u8'..."
            Remove-Item "master.m3u8" -Force
        }
        else {
            Write-Host "Skipping deletion."
        }
    }

    # Remove job_LINKS.txt if it exists.
    if (Test-Path "job_LINKS.txt") {
        Remove-Item "job_LINKS.txt" -Force
    }

    # Download the master playlist.
    Download-File -Url $MasterM3u8 -OutputFile "master.m3u8"

    # Process variant playlists found in the master playlist.
    Write-Host "-------------------"
    Write-Host "Processing variant playlists..."
    $Variants = Get-Content "master.m3u8" |
                Where-Object { $_ -notmatch '^#' } |
                ForEach-Object { $_.Trim() } |
                Select-Object -Unique |
                Sort-Object
    foreach ($Variant in $Variants) {
        if ($Variant -notmatch "\.(m3u8|mp4)$") {
            Write-Warning "'$Variant' does not end with .m3u8 or .mp4 – skipping."
            continue
        }
        if ($LogFlag -eq 1) {
            if ($Variant -match "^https?://") {
                Add-Content -Path "job_LINKS.txt" -Value $Variant
            }
            else {
                Add-Content -Path "job_LINKS.txt" -Value "$StreamM3u8/$Variant"
            }
        }
        Download-M3u8 -Playlist $Variant -BaseUrl $StreamM3u8
    }

    # Process embedded audio (or i-frame) playlists from the master playlist.
    $MasterContent = Get-Content "master.m3u8" -Raw
    $AudioMatches = [regex]::Matches($MasterContent, 'URI="([^"]*\.m3u8)"')
    $AudioTags = $AudioMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    if ($AudioTags.Count -gt 0) {
        Write-Host "-------------------"
        Write-Host "Processing audio playlists..."
        foreach ($Audio in $AudioTags) {
            if ($LogFlag -eq 1) {
                Add-Content -Path "job_LINKS.txt" -Value "$StreamM3u8/$Audio"
            }
            Download-File -Url "$StreamM3u8/$Audio" -OutputFile $Audio
            if (Test-Path $Audio) {
                $AudioVariants = Get-Content $Audio |
                                 Where-Object { $_ -notmatch '^#' } |
                                 ForEach-Object { $_.Trim() } |
                                 Select-Object -Unique |
                                 Sort-Object
                foreach ($Variant in $AudioVariants) {
                    if ($Variant -notmatch "\.(m3u8|mp4)$") {
                        Write-Warning "'$Variant' (from audio playlist) does not end with .m3u8 or .mp4 – skipping."
                        continue
                    }
                    if ($LogFlag -eq 1) {
                        Add-Content -Path "job_LINKS.txt" -Value "$StreamM3u8/$Variant"
                    }
                    Download-M3u8 -Playlist $Variant -BaseUrl $StreamM3u8
                }
            }
            else {
                Write-Error "Audio playlist file '$Audio' not found."
            }
        }
    }

    Write-Host "==== THE END. Files saved in directory: $outputDir ===="
}
#endregion

# Execute the main function with the provided master URL.
M3u8Dump -MasterM3u8 $MasterUrl
