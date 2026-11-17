import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SampleFormat: String, CaseIterable {
    case wav, mp3, m4a, flac, mp4
}

struct ShelfSample: Identifiable {
    let url: URL
    var analysis: SampleAnalysis?
    var id: URL { url }
}

struct ShelfError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ShelfTools {
    static func executable(_ name: String) -> URL? {
        let paths = [Bundle.main.resourceURL?.appendingPathComponent("Tools").path,
                     "/opt/homebrew/bin", "/usr/local/bin"].compactMap { $0 }
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func videoURL(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        let path = parts.path.split(separator: "/")
        let id: String?
        if host == "youtu.be" {
            id = path.first.map(String.init)
        } else if ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com"].contains(host) {
            if parts.path == "/watch" {
                id = parts.queryItems?.first(where: { $0.name == "v" })?.value
            } else if let kind = path.first, ["shorts", "live", "embed"].contains(kind), path.count == 2 {
                id = String(path[1])
            } else { id = nil }
        } else { id = nil }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=" + id)
    }

    static func download(_ video: URL, format: SampleFormat, into folder: URL) throws -> URL {
        guard let downloader = executable("yt-dlp"), let ffmpeg = executable("ffmpeg"),
              let ffprobe = executable("ffprobe"), let deno = executable("deno") else {
            throw ShelfError(message: "Install yt-dlp, ffmpeg, ffprobe, and Deno to download audio.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appendingPathComponent(".download-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let task = Process()
        let pipe = Pipe()
        task.executableURL = downloader
        var environment = ProcessInfo.processInfo.environment
        let paths = [ffmpeg, ffprobe, deno].map { $0.deletingLastPathComponent().path }
        environment["PATH"] = (paths + ["/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        task.environment = environment
        let formatOptions = format == .mp4
            ? ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b",
               "--merge-output-format", "mp4", "--recode-video", "mp4",
               "--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v h264_videotoolbox -b:v 6M"]
            : ["-f", "bestaudio/best", "-x", "--audio-format", format.rawValue, "--audio-quality", "0"]
        task.arguments = ["--ignore-config", "--no-playlist", "--no-progress", "--socket-timeout", "20",
                          "--js-runtimes", "deno:" + deno.path, "--restrict-filenames", "--trim-filenames", "140"]
            + formatOptions + ["-P", staging.path, "-o", "%(title)s [%(id)s].%(ext)s", "--", video.absoluteString]
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        try task.run()
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let result = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == format.rawValue }) else {
            let error = String(decoding: log, as: UTF8.self).split(whereSeparator: \.isNewline)
                .last(where: { $0.contains("ERROR:") })
            throw ShelfError(message: error.map(String.init) ?? "Couldn’t download this video.")
        }
        let destination = uniqueDestination(for: result.lastPathComponent, in: folder)
        try fm.moveItem(at: result, to: destination)
        return destination
    }
    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let original = folder.appendingPathComponent(name)
        var result = original
        var count = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = folder.appendingPathComponent(original.deletingPathExtension().lastPathComponent + " (\(count))")
                .appendingPathExtension(original.pathExtension)
            count += 1
        }
        return result
    }

    static func convert(_ source: URL, format: SampleFormat, into folder: URL) throws -> URL {
        guard let ffmpeg = executable("ffmpeg") else { throw ShelfError(message: "Audio converter is missing.") }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent("." + UUID().uuidString).appendingPathExtension(format.rawValue)
        defer { try? fm.removeItem(at: temporary) }
        let options: [String]
        switch format {
        case .wav: options = ["-map", "0:a:0", "-vn", "-c:a", "pcm_s24le"]
        case .mp3: options = ["-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-q:a", "0"]
        case .m4a: options = ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "256k"]
        case .flac: options = ["-map", "0:a:0", "-vn", "-c:a", "flac"]
        case .mp4: options = ["-map", "0:v:0", "-map", "0:a?", "-c:v", "h264_videotoolbox", "-b:v", "6M", "-pix_fmt", "yuv420p",
                              "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:a", "aac",
                              "-b:a", "256k", "-movflags", "+faststart"]
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = ffmpeg
        process.arguments = ["-nostdin", "-v", "error", "-i", source.path] + options + [temporary.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        try process.run()
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ShelfError(message: "Conversion failed. " + String(decoding: log.suffix(500), as: UTF8.self))
        }
        let name = source.deletingPathExtension().lastPathComponent + "." + format.rawValue
        let result = uniqueDestination(for: name, in: folder)
        try fm.moveItem(at: temporary, to: result)
        return result
    }

}

@MainActor
final class ShelfModel: ObservableObject {
    @Published var link = ""
    @Published var format = SampleFormat.wav
    @Published var samples: [ShelfSample] = []
    @Published private(set) var heldFiles: [URL] = []
    @Published var busy = false
    @Published var status = ""
    @Published var conversionInput: URL?
    @Published var conversionFormat = SampleFormat.wav
    @Published var converting = false
    @Published var conversionStatus = ""
    @Published private(set) var convertedFiles: [URL] = []
    private let conversions = URL.applicationSupportDirectory.appendingPathComponent("Jimbo Sample Shelf/Converted")

    func clearSamples() {
        guard !busy else { return }
        var failed: [ShelfSample] = []
        for sample in samples {
            if sample.url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                do {
                    if FileManager.default.fileExists(atPath: sample.url.path) {
                        try FileManager.default.removeItem(at: sample.url)
                    }
                } catch { failed.append(sample) }
            }
        }
        samples = failed
        status = failed.isEmpty ? "" : "Some files couldn’t be deleted."
    }

    func clearHeldFiles() {
        heldFiles.removeAll()
        saveHeldFiles()
    }

    func clearConversions() {
        guard !converting else { return }
        convertedFiles = convertedFiles.filter { file in
            do {
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
                return false
            } catch { return true }
        }
        conversionStatus = convertedFiles.isEmpty ? "" : "Some files couldn’t be deleted."
    }

    func selectConversion(_ file: URL) {
        guard !converting, file.isFileURL else { return }
        conversionInput = file
        conversionStatus = ""
    }

    func convert() {
        guard !converting, let source = conversionInput else { return }
        converting = true
        conversionStatus = "Converting…"
        let format = conversionFormat
        let folder = conversions
        Task {
            defer { converting = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ShelfTools.convert(source, format: format, into: folder)
                }.value
                convertedFiles.insert(result, at: 0)
                conversionStatus = "Ready to drag out."
            } catch { conversionStatus = error.localizedDescription }
        }
    }
    private let folder = URL.applicationSupportDirectory.appendingPathComponent("Jimbo Sample Shelf/Samples")

    init() {
        heldFiles = (UserDefaults.standard.stringArray(forKey: "heldFiles") ?? []).map {
            URL(fileURLWithPath: $0)
        }
        convertedFiles = ((try? FileManager.default.contentsOfDirectory(at: conversions, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if SampleFormat(rawValue: file.pathExtension.lowercased()) != nil { add(file) }
        }
    }

    func download() {
        guard !busy else { return }
        guard let video = ShelfTools.videoURL(link) else { status = "Paste an individual YouTube video link."; return }
        busy = true
        status = "Downloading and converting…"
        let format = format
        let folder = folder
        Task {
            defer { busy = false }
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    try ShelfTools.download(video, format: format, into: folder)
                }.value
                link = ""
                status = "Ready to drag into FL Studio."
                add(file)
            } catch { status = error.localizedDescription }
        }
    }

    func hold(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let file = url.standardizedFileURL
            if !heldFiles.contains(where: { $0.path == file.path }) {
                heldFiles.append(file)
            }
        }
        saveHeldFiles()
    }

    func removeHeldFile(_ url: URL) {
        heldFiles.removeAll { $0.path == url.path }
        saveHeldFiles()
    }

    private func saveHeldFiles() {
        UserDefaults.standard.set(heldFiles.map(\.path), forKey: "heldFiles")
    }

    func add(_ file: URL) {
        guard SampleFormat(rawValue: file.pathExtension.lowercased()) != nil,
              !samples.contains(where: { $0.url == file }) else { return }
        samples.insert(ShelfSample(url: file), at: 0)
        guard let ffmpeg = ShelfTools.executable("ffmpeg") else {
            samples[0].analysis = SampleAnalysis(bpm: nil, key: nil)
            return
        }
        Task {
            let analysis = await Task.detached(priority: .utility) { SampleAnalysis.read(file, using: ffmpeg) }.value
            if let index = samples.firstIndex(where: { $0.url == file }) { samples[index].analysis = analysis }
        }
    }
}

@MainActor
final class ShelfDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var item: NSStatusItem!
    private let shortcut = ShelfShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = ShelfModel()
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 415),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.title = "Jimbo's Shelf"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(srgbRed: 0.065, green: 0.077, blue: 0.093, alpha: 1)
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ShelfView(model: model, shortcut: shortcut,
            hide: { [weak self] in self?.hideShelf() },
            editShortcut: { [weak self] in self?.editShortcut() }))
        panel.isReleasedWhenClosed = false
        panel.center()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jimbo's Shelf")
        let menu = NSMenu()
        let toggle = menu.addItem(withTitle: "Show or Hide Shelf", action: #selector(toggleShelf), keyEquivalent: "")
        toggle.target = self
        let edit = menu.addItem(withTitle: "Change Shelf Shortcut…", action: #selector(editShortcut), keyEquivalent: "")
        edit.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Jimbo's Shelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        item.menu = menu
        shortcut.onToggle = { [weak self] in self?.toggleShelf() }
        shortcut.start()
        panel.orderFrontRegardless()
    }

    @objc private func toggleShelf() {
        if panel.isVisible { hideShelf() } else { panel.orderFrontRegardless() }
    }

    private func hideShelf() {
        shortcut.cancel()
        panel.orderOut(nil)
    }

    @objc private func editShortcut() {
        shortcut.record(in: panel)
    }

    func windowWillClose(_ notification: Notification) {
        shortcut.cancel()
    }

    func windowDidResignKey(_ notification: Notification) {
        shortcut.cancel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcut.stop()
    }
}

@main
struct SampleShelfApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ShelfDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
