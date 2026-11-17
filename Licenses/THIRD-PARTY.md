# Bundled tools

- yt-dlp 2026.10.26, official macOS release. The PyInstaller binary includes third-party components and is distributed under GPLv3+. Source and license information at https://github.com/yt-dlp/yt-dlp/tree/2026.10.26 and https://github.com/yt-dlp/yt-dlp#license .
- Deno 2.9.8, official macOS arm64 release, MIT license. Source at https://github.com/denoland/deno/tree/v2.9.8 .
- FFmpeg 7.1.1, built from source for this app under LGPLv2.1+ without GPL or nonfree build options. The converter source archive includes source and build instructions.
- LAME 3.100, statically linked into FFmpeg under LGPLv2+. Source is included in the converter source archive.

The source archive contains original license files and permits rebuilding or modifying the converter tools. They run as separate processes from the shelf app.
