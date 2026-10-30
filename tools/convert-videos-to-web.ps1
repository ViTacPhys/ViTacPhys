[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$FfmpegPath = "",
    [ValidateRange(0, 51)]
    [int]$Crf = 23,
    [ValidateSet("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow")]
    [string]$Preset = "medium"
)

$ErrorActionPreference = "Stop"

function Resolve-Ffmpeg {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "FFmpeg not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $command = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        $command = Get-Command ffmpeg -ErrorAction SilentlyContinue
    }
    if ($command) {
        return $command.Source
    }

    $bundledCandidates = @(
        "C:\Program Files\EVCapture\ffmpeg.exe",
        "C:\Program Files\ffmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\bin\ffmpeg.exe"
    )
    foreach ($candidate in $bundledCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "FFmpeg was not found. Install FFmpeg or pass -FfmpegPath C:\path\to\ffmpeg.exe."
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$videoRoot = Join-Path $root "assets\videos"
if (-not (Test-Path -LiteralPath $videoRoot -PathType Container)) {
    throw "Video directory not found: $videoRoot"
}

$ffmpeg = Resolve-Ffmpeg -RequestedPath $FfmpegPath
$videos = @(Get-ChildItem -LiteralPath $videoRoot -Filter *.mp4 -File -Recurse | Sort-Object FullName)
if ($videos.Count -eq 0) {
    throw "No MP4 videos found under $videoRoot"
}

$stagingRoot = Join-Path $root ".web-video-staging"
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

Write-Host "FFmpeg: $ffmpeg"
Write-Host "Project: $root"
Write-Host "Videos:  $($videos.Count)"
Write-Host "Codec:   H.264 (avc1), yuv420p, CRF $Crf, preset $Preset, faststart"

$converted = New-Object System.Collections.Generic.List[object]
$index = 0

try {
    foreach ($video in $videos) {
        $index++
        $relativePath = $video.FullName.Substring($videoRoot.Length).TrimStart('\', '/')
        $outputPath = Join-Path $stagingRoot $relativePath
        $outputDirectory = Split-Path -Parent $outputPath
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

        Write-Host ("[{0}/{1}] {2}" -f $index, $videos.Count, $relativePath)

        $arguments = @(
            "-hide_banner",
            "-loglevel", "warning",
            "-nostdin",
            "-y",
            "-i", $video.FullName,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", "libx264",
            "-preset", $Preset,
            "-crf", "$Crf",
            "-pix_fmt", "yuv420p",
            "-profile:v", "high",
            "-tag:v", "avc1",
            "-movflags", "+faststart",
            "-c:a", "aac",
            "-b:a", "128k",
            $outputPath
        )

        & $ffmpeg @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "FFmpeg failed for $relativePath (exit code $LASTEXITCODE). Originals were not replaced."
        }

        $outputFile = Get-Item -LiteralPath $outputPath
        if ($outputFile.Length -le 0) {
            throw "FFmpeg produced an empty file for $relativePath. Originals were not replaced."
        }
        if ($outputFile.Length -ge 95MB) {
            throw "Converted file exceeds the 95 MiB safety limit for GitHub: $relativePath. Originals were not replaced."
        }

        # Decode a short section before accepting the result. This catches corrupt
        # containers or an unavailable H.264 encoder without doubling total runtime.
        & $ffmpeg -hide_banner -loglevel error -nostdin -i $outputPath -map 0:v:0 -t 1 -f null NUL
        if ($LASTEXITCODE -ne 0) {
            throw "Validation failed for $relativePath. Originals were not replaced."
        }

        $converted.Add([PSCustomObject]@{
            RelativePath = $relativePath
            Source       = $video.FullName
            Output       = $outputPath
            OldBytes     = $video.Length
            NewBytes     = $outputFile.Length
        })
    }

    if ($converted.Count -ne $videos.Count) {
        throw "Converted $($converted.Count) of $($videos.Count) files. Originals were not replaced."
    }

    Write-Host "All staged videos passed validation. Replacing tracked video files..."
    foreach ($item in $converted) {
        Move-Item -LiteralPath $item.Output -Destination $item.Source -Force
    }

    $oldTotal = ($converted | Measure-Object -Property OldBytes -Sum).Sum
    $newTotal = ($converted | Measure-Object -Property NewBytes -Sum).Sum
    Write-Host "Done: converted $($converted.Count) videos to browser-compatible H.264."
    Write-Host ("Size: {0:N1} MiB -> {1:N1} MiB" -f ($oldTotal / 1MB), ($newTotal / 1MB))
    Write-Host "Next: review 'git status', then commit and push the changed MP4 files."
}
catch {
    Write-Error $_
    Write-Host "No original video was replaced unless every staged output had already passed validation."
    Write-Host "Staged files are kept at: $stagingRoot"
    exit 1
}

