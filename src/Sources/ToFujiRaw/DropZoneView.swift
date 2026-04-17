import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DropZoneView: View {
    @Binding var files: [URL]
    let mapping: CameraMapping
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary,
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.3)))

            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                if files.isEmpty {
                    Text("Glissez vos RAW ici").font(.headline)
                    Button("+ Ajouter des fichiers") { openPanel() }
                        .buttonStyle(.bordered)
                } else {
                    Text("\(files.count) fichier\(files.count > 1 ? "s" : "") prêt\(files.count > 1 ? "s" : "")")
                        .font(.headline)
                    Button("Vider la liste") { files.removeAll() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]  // filtrage ensuite par extension
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadFileURL() {
                urls.append(url)
            }
        }
        await MainActor.run { addFiles(urls) }
    }

    private func addFiles(_ urls: [URL]) {
        let allowed = Set(mapping.sourceExtensions.map { $0.lowercased() })
        let filtered = urls.filter { allowed.contains($0.pathExtension.lowercased()) }
        files.append(contentsOf: filtered)
        // dedupe
        var seen = Set<URL>()
        files = files.filter { seen.insert($0).inserted }
    }
}

// Extension utilitaire pour NSItemProvider
private extension NSItemProvider {
    func loadFileURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { cont in
            _ = self.loadObject(ofClass: URL.self) { url, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: url) }
            }
        }
    }
}
