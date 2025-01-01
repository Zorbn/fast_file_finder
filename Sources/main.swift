import Cocoa

// TODO: Cmd-Enter to open with ...?.
// TODO: Make theme adapt while application is running.

struct Theme {
    let foreground: CGColor
    let background: CGColor
    let border: CGColor
    let selected: CGColor
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let backgroundAlpha = 1.0
let theme =
    if app.effectiveAppearance.name == .darkAqua {
        Theme(
            foreground: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            background: CGColor(red: 0, green: 0, blue: 0, alpha: backgroundAlpha),
            border: CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
            selected: CGColor(red: 0, green: 0.8, blue: 0, alpha: 1)
        )
    } else {
        Theme(
            foreground: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            background: CGColor(red: 1, green: 1, blue: 1, alpha: backgroundAlpha),
            border: CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
            selected: CGColor(red: 0, green: 0.5, blue: 0, alpha: 1)
        )
    }

let inputFont = CTFont("Menlo" as CFString, size: 24)
let resultFont = CTFont("Menlo" as CFString, size: 16)

let attributes: [NSAttributedString.Key: Any] = [
    .font: inputFont,
    .foregroundColor: theme.foreground,
]

let resultAttributes: [NSAttributedString.Key: Any] = [
    .font: resultFont,
    .foregroundColor: theme.foreground,
]

let selectedResultAttributes: [NSAttributedString.Key: Any] = [
    .font: resultFont,
    .foregroundColor: theme.selected,
]

let maxResults = 18

class View: NSView {
    var previouslyActivateApp: NSRunningApplication?
    var inputText = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    var results: [String] = []
    var selectedResultIndex = 0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let context = NSGraphicsContext.current!.cgContext

        context.clear(bounds)

        let string =
            if inputText.isEmpty {
                "\u{200b}"  // Zero-width space.
            } else {
                inputText
            }

        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        let lineBounds = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())

        let inputX = getTextOffsetX(lineWidth: lineBounds.width)

        context.textPosition = CGPoint(x: inputX, y: bounds.height - lineBounds.height)
        CTLineDraw(line, context)

        context.setFillColor(theme.foreground)
        context.fill(
            CGRect(
                x: context.textPosition.x, y: context.textPosition.y - lineBounds.height * 0.125,
                width: 2,
                height: lineBounds.height))

        context.setFillColor(theme.border)
        context.fill(
            CGRect(
                x: 0, y: context.textPosition.y - lineBounds.height * 0.4,
                width: bounds.width,
                height: 2))

        let resultBaseAttributedString = NSAttributedString(
            string: inputText, attributes: resultAttributes)
        let resultBaseLine = CTLineCreateWithAttributedString(resultBaseAttributedString)
        let resultBaseLineBounds = CTLineGetBoundsWithOptions(resultBaseLine, CTLineBoundsOptions())

        let resultX = getTextOffsetX(lineWidth: resultBaseLineBounds.width)
        var resultY = lineBounds.height * 1.4

        for (i, result) in results.enumerated() {
            let attributes =
                if i == selectedResultIndex {
                    selectedResultAttributes
                } else {
                    resultAttributes
                }

            let icon = NSWorkspace.shared.icon(forFile: result)

            let attributedString = NSAttributedString(string: result, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            let lineBounds = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions())
            resultY += lineBounds.height

            context.textPosition = CGPoint(x: resultX, y: bounds.height - resultY)
            CTLineDraw(line, context)

            if let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.draw(
                    cgIcon,
                    in: CGRect(
                        x: bounds.width - 22, y: context.textPosition.y - 4, width: 16,
                        height: 16)
                )
            }
        }
    }

    func getTextOffsetX(lineWidth: CGFloat) -> CGFloat {
        return -max(lineWidth - bounds.width / 2, 0) + 8
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters {
            var needsResultsUpdate = true

            for c in characters {
                switch c {
                case "\u{f700}":  // Up
                    selectedResultIndex = max(selectedResultIndex - 1, 0)
                    needsResultsUpdate = false
                case "\u{f701}":  // Down
                    selectedResultIndex = min(selectedResultIndex + 1, results.count - 1)
                    needsResultsUpdate = false
                case "\t":
                    completeResult()
                case "\r":
                    completeResult()

                    // Remove trailing whitespace, allows you to type "/path/to/file " to create
                    // "file" when "/path/to/filewithlongername" exists and would otherwise get completed.
                    while inputText.last?.isWhitespace ?? false {
                        inputText.removeLast()
                    }

                    if !FileManager.default.fileExists(atPath: inputText) {
                        if inputText.last == "/" {
                            try! FileManager.default.createDirectory(
                                atPath: inputText, withIntermediateDirectories: true,
                                attributes: nil)
                        } else {
                            FileManager.default.createFile(atPath: inputText, contents: nil)
                        }
                    }

                    NSWorkspace.shared.open(URL(filePath: inputText))

                    close(doReturnActivation: false)
                case "\u{1b}":  // ESC
                    close(doReturnActivation: true)
                case "\u{f728}":  // Forward DEL
                    completeResult()

                    NSWorkspace.shared.recycle([URL(filePath: inputText)])

                    close(doReturnActivation: true)
                case "\u{7f}":  // DEL
                    if event.modifierFlags.contains(.command) {
                        inputText.removeAll()
                        break
                    }

                    if inputText.last == "/" {
                        inputText.removeLast()

                        while inputText.last != "/" && !inputText.isEmpty {
                            inputText.removeLast()
                        }

                        break
                    }

                    if event.modifierFlags.contains(.option)
                        || event.modifierFlags.contains(.control)
                    {
                        _ = inputText.popLast()

                        while !inputText.isEmpty && inputText.last != "/" {
                            inputText.removeLast()
                        }

                        break
                    }

                    _ = inputText.popLast()
                default:
                    if c.isLetter || c.isNumber || c.isSymbol || c.isPunctuation || c == " " {
                        inputText.append(c)
                    }
                }

                if needsResultsUpdate {
                    if inputText.isEmpty {
                        inputText.append("/")
                    }

                    updateResults()
                }

                setNeedsDisplay(bounds)
            }
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func completeResult() {
        if selectedResultIndex >= 0 && selectedResultIndex < results.count {
            inputText = results[selectedResultIndex]
        }
    }

    func getInputTextDirectory() -> String {
        let path =
            if let index = inputText.lastIndex(of: "/") {
                inputText[...index]
            } else {
                inputText[...]
            }

        return String(path)
    }

    func updateResults() {
        let path = getInputTextDirectory()
        let url = URL(filePath: String(path))

        results.removeAll()
        selectedResultIndex = 0

        let files: [URL]

        do {
            files = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil)
        } catch {
            return
        }

        for file in files {
            let path = file.path(percentEncoded: false)

            if path.count < inputText.count {
                continue
            }

            if path.compare(
                inputText, options: .caseInsensitive,
                range: inputText.startIndex..<inputText.endIndex) != .orderedSame
            {
                continue
            }

            results.append(path)

            if results.count >= maxResults {
                break
            }
        }

        results.sort { a, b in
            let aDotIndex = View.dotFileIndex(a)
            let bDotIndex = View.dotFileIndex(b)

            if aDotIndex == nil && bDotIndex != nil {
                return true
            }

            if bDotIndex == nil && aDotIndex != nil {
                return false
            }

            if let aDotIndex = aDotIndex {
                if let bDotIndex = bDotIndex {
                    return aDotIndex < bDotIndex
                }
            }

            if a.last == "/" && b.last != "/" {
                return true
            }

            if b.last == "/" && a.last != "/" {
                return false
            }

            return a < b
        }
    }

    class func dotFileIndex(_ string: String) -> String.Index? {
        guard let dotIndex = string.lastIndex(of: ".") else {
            return nil
        }

        if dotIndex <= string.startIndex {
            return nil
        }

        let beforeIndex = string.index(before: dotIndex)

        if string[beforeIndex] == "/" {
            return dotIndex
        }

        return nil
    }

    func close(doReturnActivation: Bool) {
        window?.close()

        if doReturnActivation {
            previouslyActivateApp?.activate(from: NSRunningApplication.current)
        }
    }
}

class Window: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func resignMain() {
        close()
    }
}

@MainActor
class Delegate: NSObject, NSApplicationDelegate {
    let view = View()
    var window: Window?

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.activate()

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.characters == "\u{a0}" && event.modifierFlags.contains(.option) {
                if let old_window = self.window.take() {
                    old_window.close()
                }

                let window = Window(
                    contentRect: NSRect(x: 0, y: 0, width: 768, height: 768 / 2),
                    styleMask: [.titled, .fullSizeContentView],
                    backing: .buffered, defer: false)

                window.isReleasedWhenClosed = false

                self.view.inputText = self.view.getInputTextDirectory()
                self.view.updateResults()

                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true

                window.level = .floating

                window.contentView = self.view
                window.center()
                window.makeKeyAndOrderFront(self)
                window.makeMain()

                self.window = window

                for running_app in NSWorkspace.shared.runningApplications {
                    if running_app.isActive {
                        self.view.previouslyActivateApp = running_app
                        NSRunningApplication.current.activate(from: running_app)
                        return
                    }
                }

                self.view.previouslyActivateApp = nil
                app.activate()
            }
        }
    }
}

let delegate = Delegate()
app.delegate = delegate

app.run()
