import Foundation

struct ProcessOutput {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        input: Data? = nil
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            stdinPipe = nil
        }

        let stdoutCollector = DataCollector()
        let stderrCollector = DataCollector()
        stdoutCollector.attach(to: stdoutPipe.fileHandleForReading)
        stderrCollector.attach(to: stderrPipe.fileHandleForReading)

        try process.run()

        if let input, let stdinPipe {
            stdinPipe.fileHandleForWriting.write(input)
            stdinPipe.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        stdoutCollector.waitForEOF()
        stderrCollector.waitForEOF()

        return ProcessOutput(
            stdout: stdoutCollector.data,
            stderr: stderrCollector.data,
            exitCode: process.terminationStatus
        )
    }
}

private final class DataCollector {
    private let lock = NSLock()
    private let eof = DispatchSemaphore(value: 0)
    private(set) var data = Data()
    private var didSignalEOF = false

    func attach(to handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fh in
            guard let self else { return }
            let chunk = fh.availableData
            if chunk.isEmpty {
                fh.readabilityHandler = nil
                self.signalEOF()
                return
            }
            self.lock.lock()
            self.data.append(chunk)
            self.lock.unlock()
        }
    }

    func waitForEOF() {
        eof.wait()
    }

    private func signalEOF() {
        lock.lock()
        defer { lock.unlock() }
        guard !didSignalEOF else { return }
        didSignalEOF = true
        eof.signal()
    }
}
