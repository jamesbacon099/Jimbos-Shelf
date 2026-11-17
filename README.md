# Jimbo's Shelf

A floating file shelf, YouTube audio/video downloader, and media converter for macOS.

## Download

Get **Jimbos-Shelf-macOS-arm64.zip** from [the latest release](https://github.com/jamesbacon099/Jimbos-Shelf/releases/latest). Unzip it and move **Jimbo's Shelf.app** into Applications.

Requires an Apple Silicon Mac with macOS 14.2 or newer. The app is locally signed and has not been notarized by Apple. If macOS blocks it, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway**.

## Use

- **Sampler** downloads WAV, MP3, M4A, FLAC, and MP4 files and estimates key and BPM.
- **Files** holds files and folders while you switch apps.
- **Convert** converts audio, extracts it from video, and exports MP4 from video.
- Drag completed files into FL Studio or another app.
- Click **Hide**, or use the **Show / hide shortcut**. The initial shortcut is **Control–Option–Command–J**. Click **Change** to record your own.
- The menu bar waveform icon can show the shelf again.
- **Clear** in Sampler or Convert permanently deletes generated files after confirmation. Files clears references to originals.

BPM and key are estimates calculated locally. Download content you have permission to use.

## Build

Install the Xcode Command Line Tools. Put executable copies of yt-dlp, deno, ffmpeg, and ffprobe in .tools/, then run `bash build-app.sh`. The output is written to ../outputs/.

## Third-party tools

See [Licenses](Licenses/THIRD-PARTY.md). The release includes source code and build instructions for the bundled FFmpeg and LAME binaries.
