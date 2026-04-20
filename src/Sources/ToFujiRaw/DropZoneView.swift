import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DropZoneView: View {
    @Binding var files: [URL]
    let mapping: CameraMapping
    let isDisabled: Bool
    @State private var isTargeted = false

    var body: some View {
        let borderColor = isTargeted ? Theme.cyan : Theme.ink
        let fillColor = isTargeted ? Theme.cyan.opacity(0.12) : Color.white.opacity(0.45)

        ZStack {
            Rectangle()
                .fill(fillColor)
            Rectangle()
                .stroke(borderColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))

            VStack(spacing: 10) {
                Image(systemName: files.isEmpty ? "tray.and.arrow.down" : "photo.stack")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(borderColor)

                if files.isEmpty {
                    Text("DROP \(mapping.sourceExtensions.map { ".\($0.uppercased())" }.joined(separator: " / ")) HERE")
                        .font(Theme.monoTitle)
                        .foregroundStyle(Theme.ink)
                    Button("+ ADD FILES") { openPanel() }
                        .buttonStyle(RetroButtonStyle(color: Theme.cream, textColor: Theme.ink, isEnabled: !isDisabled))
                        .disabled(isDisabled)
                } else {
                    HStack(spacing: 8) {
                        RetroChip(label: "\(files.count) READY", color: Theme.magenta)
                        RetroChip(label: mapping.sourceExtensions.joined(separator: " / "))
                    }
                    Button("CLEAR LIST") { files.removeAll() }
                        .buttonStyle(RetroButtonStyle(color: Theme.cream, textColor: Theme.ink, isEnabled: !isDisabled))
                        .disabled(isDisabled)
                }
            }
            .padding()
        }
        .opacity(isDisabled ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard !isDisabled else { return false }
            handleDrop(providers)
            return true
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        var hasFinished = false

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            guard !hasFinished else { return }
            hasFinished = true
            let dropped = urls
            DispatchQueue.main.async {
                addFiles(dropped)
            }
        }

        for provider in providers {
            group.enter()
            provider.loadFileURL { url in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .userInitiated)) { finish() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            finish()
        }
    }

    private func addFiles(_ urls: [URL]) {
        let allowed = Set(mapping.sourceExtensions.map { $0.lowercased() })
        let filtered = urls.filter { allowed.contains($0.pathExtension.lowercased()) }
        files.append(contentsOf: filtered)
        var seen = Set<URL>()
        files = files.filter { seen.insert($0).inserted }
    }
}

private extension NSItemProvider {
    func loadFileURL(_ completion: @escaping (URL?) -> Void) {
        _ = self.loadObject(ofClass: URL.self) { url, _ in
            completion(url)
        }
    }
}
