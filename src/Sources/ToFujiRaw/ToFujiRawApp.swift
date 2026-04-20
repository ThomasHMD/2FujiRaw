import SwiftUI

/// Entry point : bascule entre mode CLI (`--cli`) et mode GUI SwiftUI.
@main
struct Entry {
    static func main() {
        if CommandLine.arguments.contains("--cli") {
            CLI.run()
        }
        ToFujiRawApp.main()
    }
}

struct ToFujiRawApp: App {
    var body: some Scene {
        Window("2FujiRaw", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 620)
    }
}
