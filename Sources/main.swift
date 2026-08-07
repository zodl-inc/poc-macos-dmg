import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.title = "Hello World"
window.center()

let label = NSTextField(labelWithString: "Hola Mundo 👋")
label.font = NSFont.systemFont(ofSize: 36, weight: .bold)
label.alignment = .center
label.frame = NSRect(x: 0, y: 70, width: 400, height: 60)
window.contentView?.addSubview(label)

let version = NSTextField(labelWithString: "v1.0.0")
version.font = NSFont.systemFont(ofSize: 12)
version.textColor = .secondaryLabelColor
version.alignment = .center
version.frame = NSRect(x: 0, y: 40, width: 400, height: 20)
window.contentView?.addSubview(version)

window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApplications: true)

// Check for updates at launch (after 3s so window appears first) and every hour
DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    Updater.checkAndUpdate()
}
Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    DispatchQueue.global().async { Updater.checkAndUpdate() }
}

app.run()
