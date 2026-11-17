import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ShelfTypography {
    static let body = "HelveticaNeue"
    static let labels = "HelveticaNeue-Medium"
}

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var shortcut: ShelfShortcut
    let hide: () -> Void
    let editShortcut: () -> Void
    @State private var section = Section.samples
    @State private var dropTargeted = false
    @State private var confirmsClear = false
    @State private var lightPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.48, green: 0.82, blue: 1.0)
    private let textColor = Color(red: 0.89, green: 0.94, blue: 0.98)
    private let surface = Color(red: 0.065, green: 0.077, blue: 0.093)

    private enum Section: String, CaseIterable {
        case samples = "Sampler"
        case files = "Files"
        case convert = "Convert"
    }

    var body: some View {
        let destination = section
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ShelfLEDTitle()
                Spacer(minLength: 6)
                Button(action: hide) { Label("Hide", systemImage: "chevron.down") }
            }
            .font(.custom(ShelfTypography.labels, size: 13))

            HStack(spacing: 8) {
                Label("Show / hide shortcut", systemImage: "keyboard")
                    .foregroundStyle(textColor.opacity(0.8))
                Text(shortcut.recording ? "Press your shortcut…" : shortcut.label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                Button(shortcut.recording ? "Cancel" : "Change", action: editShortcut)
                    .help("Choose the shortcut that shows or hides Jimbo’s Shelf from any app.")
            }
            .font(.custom(ShelfTypography.labels, size: 12))

            HStack(spacing: 5) {
                ForEach(Section.allCases, id: \.self) { tab in
                    Button {
                        section = tab
                    } label: {
                        Text(tab.rawValue.uppercased())
                            .font(.custom(ShelfTypography.labels, size: 14))
                            .tracking(1.5)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .foregroundStyle(section == tab ? surface : accent)
                            .background(section == tab ? accent : .clear, in: RoundedRectangle(cornerRadius: 4))
                            .shadow(color: section == tab ? accent.opacity(0.26) : .clear, radius: 5)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: section)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == tab ? .isSelected : [])
                }
                Spacer()
                if section == .files {
                    Button("Add…", systemImage: "plus") { chooseFiles() }
                }
                Button("Clear") {
                    if section == .files { model.clearHeldFiles() } else { confirmsClear = true }
                }
                .disabled(section == .samples ? model.busy || model.samples.isEmpty
                          : section == .convert ? model.converting || model.convertedFiles.isEmpty
                          : model.heldFiles.isEmpty)
                .font(.custom(ShelfTypography.labels, size: 13))
            }
            if !shortcut.message.isEmpty {
                Text(shortcut.message).font(.custom(ShelfTypography.body, size: 13))
            }

            VStack(alignment: .leading, spacing: 9) {
                switch section {
                case .samples: samples
                case .files: files
                case .convert: converter
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { mixerBed }
            .clipShape(.rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(accent.opacity(dropTargeted ? 0.95 : 0.40), lineWidth: dropTargeted ? 2 : 1)
                    .shadow(color: accent.opacity(dropTargeted ? 0.5 : 0), radius: 8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: dropTargeted)
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(accent, lineWidth: 1.5)
                    .phaseAnimator([false, true, false], trigger: lightPulse) { content, lit in
                        content.opacity(lit ? 0.85 : 0)
                            .shadow(color: accent.opacity(lit ? 0.45 : 0), radius: 9)
                    } animation: { _ in
                        reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.24)
                    }
                    .allowsHitTesting(false)
            }
        }
        .padding(16)
        .frame(width: 520, height: 415)
        .background(surface)
        .foregroundStyle(textColor)
        .tint(accent)
        .buttonStyle(ShelfLEDButtonStyle())
        .simultaneousGesture(TapGesture().onEnded { lightPulse += 1 })
        .onChange(of: model.samples.count) { _, _ in lightPulse += 1 }
        .onChange(of: model.heldFiles.count) { _, _ in lightPulse += 1 }
        .onChange(of: model.convertedFiles.count) { _, _ in lightPulse += 1 }
        .onChange(of: model.status) { _, _ in lightPulse += 1 }
        .onChange(of: model.conversionStatus) { _, _ in lightPulse += 1 }
        .onChange(of: shortcut.recording) { _, _ in lightPulse += 1 }
        .environment(\.colorScheme, .dark)
        .confirmationDialog("Delete generated files to free storage?", isPresented: $confirmsClear) {
            Button("Delete Files", role: .destructive) {
                if section == .samples { model.clearSamples() }
                if section == .convert { model.clearConversions() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes files created in this tab. Any projects that still use them may need you to locate the audio again. Imported originals stay in their folders.")
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            accept(providers, into: destination)
        }
    }

    private var mixerBed: some View {
        LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.15),
                                Color(red: 0.045, green: 0.055, blue: 0.07)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var samples: some View {
        Group {
            HStack(spacing: 8) {
                TextField("Paste YouTube link", text: $model.link)
                    .font(.custom(ShelfTypography.body, size: 15))
                    .onSubmit { model.download() }
                Picker("Format", selection: $model.format) {
                    ForEach(SampleFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Download") { model.download() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.link.isEmpty)
            }
            .font(.custom(ShelfTypography.labels, size: 14))
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.custom(ShelfTypography.body, size: 13))
                    .foregroundStyle(textColor.opacity(0.88))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if model.samples.isEmpty {
                empty("No samples", description: "Paste a link or drop audio or video here.", icon: "waveform")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.samples) { sample in
                            row(sample.url, detail: details(sample), icon: "waveform")
                                .contextMenu { finderButton(sample.url) }
                        }
                    }
                }
            }
        }
    }

    private var files: some View {
        Group {
            if model.heldFiles.isEmpty {
                empty("Drop files here", description: "Drag them back out when you reach the app or tab you want.", icon: "tray")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.heldFiles, id: \.self) { file in
                            row(file, detail: file.pathExtension.isEmpty ? "FILE OR FOLDER" : file.pathExtension.uppercased(),
                                icon: "doc")
                                .contextMenu {
                                    finderButton(file)
                                    Button("Remove from Shelf") { model.removeHeldFile(file) }
                                }
                        }
                    }
                }
            }
        }
    }

    private var converter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.conversionInput?.lastPathComponent ?? "Drop audio or video here")
                    .font(.custom(ShelfTypography.body, size: 15))
                    .lineLimit(1)
                Spacer()
                Button("Choose File…") { chooseConversion() }
                    .disabled(model.converting)
            }
            HStack {
                Picker("Convert to", selection: $model.conversionFormat) {
                    ForEach(SampleFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Button("Convert") { model.convert() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.converting || model.conversionInput == nil)
            }
            Text(model.conversionStatus.isEmpty
                 ? "Extract audio from video, or convert video to MP4."
                 : model.conversionStatus)
                .font(.custom(ShelfTypography.body, size: 12))
                .foregroundStyle(textColor.opacity(0.80))
                .lineLimit(3)
                .textSelection(.enabled)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.convertedFiles, id: \.self) { file in
                        row(file, detail: file.pathExtension.uppercased(), icon: "arrow.triangle.2.circlepath")
                            .contextMenu { finderButton(file) }
                    }
                }
            }
        }
        .font(.custom(ShelfTypography.labels, size: 13))
    }

    private func chooseConversion() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.audio, .movie]
        picker.begin { response in
            if response == .OK, let file = picker.url { model.selectConversion(file) }
        }
    }

    private func row(_ url: URL, detail: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 28, height: 32)
                .background(accent.opacity(0.07), in: .rect(cornerRadius: 4))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accent.opacity(0.85))
                        .frame(width: 2)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.custom(ShelfTypography.body, size: 16))
                    .lineLimit(1)
                Text(detail)
                    .font(.custom(ShelfTypography.labels, size: 12))
                    .foregroundStyle(textColor.opacity(0.72))
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal").foregroundStyle(accent.opacity(0.65))
        }
        .padding(8)
        .background(surface.opacity(0.96), in: .rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onDrag {
            lightPulse += 1
            return NSItemProvider(object: url as NSURL)
        }
    }

    private func empty(_ title: String, description: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 27, weight: .light)).foregroundStyle(accent)
            Text(title).font(.custom(ShelfTypography.body, size: 23))
            Text(description).font(.custom(ShelfTypography.body, size: 14)).foregroundStyle(textColor.opacity(0.80))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finderButton(_ url: URL) -> some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func chooseFiles() {
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = true
        picker.begin { response in
            if response == .OK { model.hold(picker.urls) }
        }
    }

    private func accept(_ providers: [NSItemProvider], into destination: Section) -> Bool {
        let type = UTType.fileURL.identifier
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(type) }
        for provider in files {
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                guard let data, let file = URL(dataRepresentation: data, relativeTo: nil), file.isFileURL else { return }
                Task { @MainActor in
                    if destination == .convert {
                        model.selectConversion(file)
                    } else if destination == .samples, SampleFormat(rawValue: file.pathExtension.lowercased()) != nil {
                        model.add(file)
                    } else {
                        model.hold([file])
                        section = .files
                    }
                }
            }
        }
        return !files.isEmpty
    }

    private func details(_ sample: ShelfSample) -> String {
        let format = sample.url.pathExtension.uppercased()
        guard let analysis = sample.analysis else { return "\(format)  ·  Analyzing…" }
        let tempo = analysis.bpm.map { "\($0) BPM" } ?? "BPM unknown"
        return "\(format)  ·  \(tempo)  ·  \(analysis.key ?? "Key unknown")"
    }
}
