import SwiftUI
import AppKit

// MARK: - App entry point (mirrors zodlmac_internalApp.swift pattern)

@main
struct ZodlPocApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var didFinishLaunching = false
    @State private var didEnterBackgroundOnce = false
    @StateObject private var logStore = LogStore()

    var body: some Scene {
        Window("", id: "main") {
            ContentView(logStore: logStore)
                .frame(width: 500, height: 420)
                .background(FixedWindowConfigurator())
                .onAppear {
                    guard !didFinishLaunching else { return }
                    didFinishLaunching = true
                    logStore.log("App started — v\(Updater.currentVersion)")
                    logStore.log("📍 Path: \(Bundle.main.bundlePath)")
                    logStore.log("👤 Home: \(NSHomeDirectory())")
                    // Check for updates 3s after launch (same delay as before)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        Updater.checkAndUpdate(log: logStore.log)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        if didEnterBackgroundOnce {
                            // Poll on foreground (mirrors iOS willEnterForeground)
                            DispatchQueue.global().async {
                                Updater.checkAndUpdate(log: logStore.log)
                            }
                        }
                    case .background:
                        didEnterBackgroundOnce = true
                    default:
                        break
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 420)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// MARK: - Log store (shared observable state for the console view)

final class LogStore: ObservableObject {
    @Published var lines: [String] = []

    func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)"
        print(line)
        DispatchQueue.main.async { self.lines.append(line) }
    }
}

// MARK: - Main window UI

struct ContentView: View {
    @ObservedObject var logStore: LogStore

    var body: some View {
        VStack(spacing: 4) {
            Text("Zodl macOS PoC")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 16)

            Text("v\(Updater.currentVersion)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logStore.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(6)
                }
                .background(Color(white: 0.08))
                .cornerRadius(4)
                .padding([.horizontal, .bottom], 10)
                .onChange(of: logStore.lines.count) { _, _ in
                    if let last = logStore.lines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - Window configurator (mirrors FixedWindowConfigurator in zodlmac)

private struct FixedWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfigView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ConfigView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.remove(.resizable)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            let fixed = NSSize(width: 500, height: 420)
            window.contentMinSize = fixed
            window.contentMaxSize = fixed
            window.isRestorable = false
            window.title = ""
            NSApp.changeWindowsItem(window, title: "Zodl", filename: false)
        }
    }
}
