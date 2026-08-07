import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "Hello World"
window.center()

let label = NSTextField(labelWithString: "Hello World 👋")
label.font = NSFont.systemFont(ofSize: 36, weight: .bold)
label.alignment = .center
label.frame = NSRect(x: 0, y: 360, width: 500, height: 50)
window.contentView?.addSubview(label)

let version = NSTextField(labelWithString: "v1.0.23")
version.font = NSFont.systemFont(ofSize: 12)
version.textColor = .secondaryLabelColor
version.alignment = .center
version.frame = NSRect(x: 0, y: 338, width: 500, height: 20)
window.contentView?.addSubview(version)

// Log console
let scrollView = NSScrollView(frame: NSRect(x: 10, y: 10, width: 480, height: 320))
scrollView.hasVerticalScroller = true
scrollView.borderType = .bezelBorder
let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))
textView.isEditable = false
textView.isSelectable = true
textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
textView.backgroundColor = NSColor(white: 0.08, alpha: 1)
textView.textColor = .green
textView.textContainerInset = NSSize(width: 6, height: 6)
scrollView.documentView = textView
window.contentView?.addSubview(scrollView)

func log(_ msg: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(ts)] \(msg)\n"
    print(line, terminator: "")
    DispatchQueue.main.async {
        textView.textStorage?.append(NSAttributedString(
            string: line,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.green
            ]
        ))
        textView.scrollToEndOfDocument(nil)
    }
}

window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
log("App started — v1.0.23")

DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    Updater.checkAndUpdate(log: log)
}
Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    DispatchQueue.global().async { Updater.checkAndUpdate(log: log) }
}

app.run()
