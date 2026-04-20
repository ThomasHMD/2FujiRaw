import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @State private var files: [URL] = []
    @State private var mapping: CameraMapping = .default
    @State private var donorFile: URL?
    @State private var preserveOriginalLeicaBodyInfo = false
    @State private var isConverting = false
    @State private var progress = ConversionProgress(
        processed: 0,
        total: 0,
        currentPhase: nil,
        currentFileFraction: 0,
        lastOutput: nil
    )
    @State private var errorMessage: String?
    @State private var lastOutputDir: URL?
    @State private var totalConverted: Int = 0

    private var hasBundledDonorTemplate: Bool {
        BundledTools.hasEmbeddedX2DDonorTemplate
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                divider

                DropZoneView(files: $files, mapping: mapping, isDisabled: isConverting)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)

                divider

                mappingSection
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)

                if mapping.requiresDonor {
                    divider

                    donorSection
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                }

                if mapping.hasLeicaSource {
                    divider

                    preserveBodyInfoSection
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                }

                divider

                actionSection
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)

                if errorMessage != nil {
                    divider
                    errorBanner
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }

                divider

                footer
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 540, height: 620)
    }

    // MARK: - Separator

    private var divider: some View {
        Rectangle()
            .fill(Theme.ink.opacity(0.12))
            .frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("2FUJIRAW")
                    .font(Theme.monoLarge)
                    .foregroundStyle(Theme.magenta)
                    .tracking(1)
                Text("RAW CAMERA SPOOFER // FUJI + HASSELBLAD TARGETS")
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            RetroChip(label: "v0.1.0", color: Theme.ink)
        }
    }

    // MARK: - Mapping picker (neutre — subordonné à CONVERT)

    private var mappingSection: some View {
        HStack(spacing: 12) {
            Text("MAPPING")
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 70, alignment: .leading)

            Menu {
                ForEach(CameraMapping.all) { m in
                    Button {
                        mapping = m
                    } label: {
                        Text(m.label)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(mapping.label)
                        .font(Theme.monoBody)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Rectangle().fill(Color.white))
                .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1.5))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(isConverting)

            Spacer()
        }
    }

    private var donorSection: some View {
        HStack(spacing: 12) {
            Text(mapping.donorLabel?.uppercased() ?? "DONOR")
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 70, alignment: .leading)

            Button(donorButtonLabel) {
                pickDonor()
            }
            .buttonStyle(RetroButtonStyle(
                color: Theme.cream,
                textColor: Theme.ink,
                isEnabled: !isConverting))
            .disabled(isConverting)

            if donorFile != nil || hasBundledDonorTemplate {
                Button(donorFile == nil ? "RESET" : "CLEAR") {
                    donorFile = nil
                }
                .buttonStyle(RetroButtonStyle(
                    color: Theme.cream,
                    textColor: Theme.ink,
                    isEnabled: !isConverting))
                .disabled(isConverting)
            }

            Spacer()
        }
    }

    private var preserveBodyInfoSection: some View {
        HStack(spacing: 12) {
            Text("METADATA")
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 70, alignment: .leading)

            Toggle(isOn: $preserveOriginalLeicaBodyInfo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRESERVE ORIGINAL LEICA BODY NAME")
                        .font(Theme.monoBody)
                        .foregroundStyle(Theme.ink)
                    Text("Replace only the displayed camera model string")
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(isConverting)

            Spacer()
        }
    }

    // MARK: - Action section (bouton + progression)

    private var actionSection: some View {
        Group {
            if isConverting {
                VStack(alignment: .leading, spacing: 10) {
                    SegmentedProgressBar(
                        done: Int(progress.overallFraction * 1000),
                        total: 1000
                    )
                    HStack {
                        Text(progressLabel)
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(progress.currentPhase ?? "PLEASE WAIT…")
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.magenta)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    Button(action: { Task { await runConversion() } }) {
                        Text("▶  CONVERT")
                    }
                    .buttonStyle(RetroButtonStyle(
                        color: Theme.magenta,
                        textColor: .white,
                        isEnabled: canConvert))
                    .disabled(!canConvert)

                    if let dir = lastOutputDir {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([dir]) }) {
                            Text("OPEN OUTPUT")
                        }
                        .buttonStyle(RetroButtonStyle(
                            color: Theme.cream,
                            textColor: Theme.ink,
                            isEnabled: true))
                    }

                    Spacer()

                    if !files.isEmpty {
                        Text(statusSummary)
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
    }

    // MARK: - Error banner

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("ERR")
                .font(Theme.monoCaption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.error)
            Text(errorMessage ?? "")
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.error)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Footer (compact, 1 ligne calme)

    private var footer: some View {
        HStack(spacing: 0) {
            RetroChip(label: "SCORE \(totalConverted)", color: Theme.limeCrt)

            Spacer()

            Text("cuisiné par Thomas Hammoudi")
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.inkSoft)

            Spacer()

            Text("swift + exiftool + dnglab")
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: - Logic

    private var canConvert: Bool {
        !files.isEmpty && (!mapping.requiresDonor || donorFile != nil || hasBundledDonorTemplate)
    }

    private var statusSummary: String {
        if mapping.requiresDonor && donorFile == nil && !hasBundledDonorTemplate {
            return "\(files.count) FILE\(files.count > 1 ? "S" : "") · X2D TEMPLATE NEEDED"
        }
        if mapping.requiresDonor && donorFile == nil && hasBundledDonorTemplate {
            return "\(files.count) FILE\(files.count > 1 ? "S" : "") · USING BUNDLED X2D TEMPLATE"
        }
        return "\(files.count) FILE\(files.count > 1 ? "S" : "") READY"
    }

    private var donorButtonLabel: String {
        if let donorFile {
            return donorFile.lastPathComponent
        }
        if hasBundledDonorTemplate {
            return "BUNDLED X2D TEMPLATE"
        }
        return "SELECT TEMPLATE OVERRIDE"
    }

    private var progressLabel: String {
        guard progress.total > 0 else { return "CONVERTING" }
        let percent = Int((progress.overallFraction * 100).rounded())
        let activeFile = min(progress.processed + 1, progress.total)
        return "FILE \(activeFile) / \(progress.total) · \(percent)%"
    }

    private func pickDonor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        if panel.runModal() == .OK {
            donorFile = panel.url
        }
    }

    func runConversion() async {
        errorMessage = nil
        isConverting = true
        progress = ConversionProgress(
            processed: 0,
            total: files.count,
            currentPhase: "STARTING",
            currentFileFraction: 0,
            lastOutput: nil
        )

        let engine = ConversionEngine(
            mapping: mapping,
            donorURL: donorFile,
            options: ConversionOptions(
                preserveOriginalLeicaBodyInfo: preserveOriginalLeicaBodyInfo
            )
        )
        let batchCount = files.count
        do {
            for try await p in engine.convertBatch(files) {
                progress = p
                if let out = p.lastOutput { lastOutputDir = out.deletingLastPathComponent() }
            }
            totalConverted += batchCount
            files = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isConverting = false
    }
}
