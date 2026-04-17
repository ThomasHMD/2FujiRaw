import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var files: [URL] = []
    @State private var mapping: CameraMapping = .default
    @State private var isConverting = false
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var errorMessage: String?
    @State private var lastOutputDir: URL?

    var body: some View {
        VStack(spacing: 16) {
            Text("2FujiRaw").font(.largeTitle).bold()
            Text("Hasselblad → Fuji look for Lightroom")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            DropZoneView(files: $files, mapping: mapping)
                .frame(maxHeight: 180)

            Picker("Mapping", selection: $mapping) {
                ForEach(CameraMapping.all) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.menu)
            .disabled(isConverting)

            if isConverting {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                Text("\(progress.done) / \(progress.total)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Button("Convertir") {
                    Task { await runConversion() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(files.isEmpty)
            }

            if let dir = lastOutputDir, !isConverting {
                Button("Ouvrir le dossier") {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                .buttonStyle(.bordered)
            }

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }

    func runConversion() async {
        errorMessage = nil
        isConverting = true
        progress = (0, files.count)

        let engine = ConversionEngine(mapping: mapping)
        do {
            for try await p in engine.convertBatch(files) {
                progress = (p.processed, p.total)
                if let out = p.lastOutput { lastOutputDir = out.deletingLastPathComponent() }
            }
            files = [] // reset liste après succès
        } catch {
            errorMessage = error.localizedDescription
        }
        isConverting = false
    }
}
