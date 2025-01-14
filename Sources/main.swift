import Cocoa
import HotKey

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let inputFont = CTFont("Menlo" as CFString, size: 24)
let resultFont = CTFont("Menlo" as CFString, size: 16)
let backgroundAlpha = 1.0
let maxResults = 18
let fuzzyMaxDepth = 4

@MainActor
struct Theme {
    let foreground: CGColor
    let background: CGColor
    let border: CGColor
    let selected: CGColor

    var appearanceName: NSAppearance.Name?

    let attributes: [NSAttributedString.Key: Any]
    let resultAttributes: [NSAttributedString.Key: Any]
    let selectedResultAttributes: [NSAttributedString.Key: Any]

    init(foreground: CGColor, background: CGColor, border: CGColor, selected: CGColor) {
        self.foreground = foreground
        self.background = background
        self.border = border
        self.selected = selected

        attributes = [
            .font: inputFont,
            .foregroundColor: foreground,
        ]

        resultAttributes = [
            .font: resultFont,
            .foregroundColor: foreground,
        ]

        selectedResultAttributes = [
            .font: resultFont,
            .foregroundColor: selected,
        ]
    }

    static let LIGHT =
        Theme(
            foreground: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            background: CGColor(red: 1, green: 1, blue: 1, alpha: backgroundAlpha),
            border: CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
            selected: CGColor(red: 0, green: 0.5, blue: 0, alpha: 1)
        )

    static let DARK =
        Theme(
            foreground: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            background: CGColor(red: 0, green: 0, blue: 0, alpha: backgroundAlpha),
            border: CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
            selected: CGColor(red: 0, green: 0.8, blue: 0, alpha: 1)
        )

    static func forEffectiveAppearance() -> Theme {
        var theme =
            if app.effectiveAppearance.name == .darkAqua {
                Theme.DARK
            } else {
                Theme.LIGHT
            }

        theme.appearanceName = app.effectiveAppearance.name

        return theme
    }
}

struct SortFile {
    let fileIndex: Int
    let score: Double
}

func asciiToLowercase(value: UInt8) -> UInt8 {
    if value > 64 && value < 91 {
        value + 32
    } else {
        value
    }
}

func compareFileScore(a: SortFile, b: SortFile) -> Bool {
    a.score > b.score
}

func scoreFuzzyMatch(haystack: Substring.UTF8View, needle: Substring.UTF8View) -> Double {
    let awardDistanceFalloff = 0.8
    let awardMatchBonus = 1.0
    let awardMaxAfterMismatch = 1.0

    var needleIndex = needle.startIndex
    var haystackIndex = haystack.startIndex

    var score = 0.0
    var nextMatchAward = 1.0

    while needleIndex < needle.endIndex && haystackIndex < haystack.endIndex {
        let lowercaseNeedleChar = asciiToLowercase(value: needle[needleIndex])
        let lowercaseHaystackChar = asciiToLowercase(value: haystack[haystackIndex])

        if lowercaseNeedleChar == lowercaseHaystackChar {
            score += nextMatchAward
            nextMatchAward += awardMatchBonus

            needleIndex = needle.index(after: needleIndex)
        }

        nextMatchAward = min(awardMaxAfterMismatch, nextMatchAward * awardDistanceFalloff)

        haystackIndex = haystack.index(after: haystackIndex)
    }

    return score
}

enum FindMode {
    case Normal
    case Fuzzy(directory: String, files: [String]?)
}

class View: NSView {
    var mode = FindMode.Normal
    var inputText = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    var results: [String] = []
    var selectedResultIndex = 0
    var theme = Theme.forEffectiveAppearance()

    var sortCache: [SortFile] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if theme.appearanceName != app.effectiveAppearance.name {
            theme = .forEffectiveAppearance()
        }

        let context = NSGraphicsContext.current!.cgContext

        context.clear(bounds)

        let string =
            if inputText.isEmpty {
                "\u{200b}"  // Zero-width space.
            } else {
                inputText
            }

        let attributedString = NSAttributedString(string: string, attributes: theme.attributes)
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

        let resultBase = getResultBase()
        let resultBaseAttributedString = NSAttributedString(
            string: resultBase, attributes: theme.attributes)
        let resultBaseLine = CTLineCreateWithAttributedString(resultBaseAttributedString)
        let resultBaseLineBounds = CTLineGetBoundsWithOptions(resultBaseLine, CTLineBoundsOptions())

        let resultX = resultBaseLineBounds.width + inputX
        var resultY = lineBounds.height * 1.4

        for (i, result) in results.enumerated() {
            let attributes =
                if i == selectedResultIndex {
                    theme.selectedResultAttributes
                } else {
                    theme.resultAttributes
                }

            let icon = NSWorkspace.shared.icon(forFile: result)

            let resultFileName = String(result[resultBase.endIndex...])

            let attributedString = NSAttributedString(
                string: resultFileName, attributes: attributes)
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
        guard let characters = event.characters else {
            return
        }

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
                mode = .Normal
            case "\r":
                completeResult()

                // Remove trailing whitespace, allows you to type "/path/to/file " to create
                // "file" when "/path/to/filewithlongername" exists and would otherwise get completed.
                while inputText.last?.isWhitespace ?? false {
                    inputText.removeLast()
                }

                if !FileManager.default.fileExists(atPath: inputText) {
                    let directory = getInputTextDirectory()
                    try! FileManager.default.createDirectory(
                        atPath: directory, withIntermediateDirectories: true,
                        attributes: nil)

                    if inputText.last != "/" {
                        FileManager.default.createFile(atPath: inputText, contents: nil)
                    }
                }

                let url = URL(filePath: inputText)

                if event.modifierFlags.contains(.command) {
                    if let terminalUrl = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.Terminal")
                    {
                        NSWorkspace.shared.open(
                            [url], withApplicationAt: terminalUrl,
                            configuration: NSWorkspace.OpenConfiguration())
                    }
                } else {
                    NSWorkspace.shared.open(url)
                }

                close()
            case "\u{1b}":  // ESC
                close()
            case "\u{f728}":  // Forward DEL
                completeResult()

                NSWorkspace.shared.recycle([URL(filePath: inputText)])

                close()
            case "\u{7f}":  // DEL
                if event.modifierFlags.contains(.command) {
                    inputText.removeAll(keepingCapacity: true)
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
                if c == "t" && event.modifierFlags.contains(.command) {
                    mode = .Fuzzy(directory: getInputTextDirectory(), files: nil)
                } else if c.isLetter || c.isNumber || c.isSymbol || c.isPunctuation || c == " " {
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

    override var acceptsFirstResponder: Bool {
        true
    }

    func completeResult() {
        if selectedResultIndex >= 0 && selectedResultIndex < results.count {
            inputText = results[selectedResultIndex]
        }
    }

    func getResultBase() -> String {
        switch mode {
        case .Normal: getInputTextDirectory()
        case .Fuzzy(let directory, _): directory
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
        results.removeAll(keepingCapacity: true)
        selectedResultIndex = 0

        switch mode {
        case .Normal:
            updateResultsNormal()
        case .Fuzzy(let directory, var files):
            if !inputText.hasPrefix(directory) {
                mode = .Normal
                return updateResults()
            }

            if files == nil {
                files = getAllFilesInDirectory(directory, maxDepth: fuzzyMaxDepth)
                mode = .Fuzzy(directory: directory, files: files)
            }

            updateResultsFuzzy(directory: directory, files: files!)
        }
    }

    func updateResultsFuzzy(directory: String, files: [String]) {
        let diffStart = directory.endIndex

        if inputText.count <= directory.count {
            return updateResultsNormal()
        }

        let inputText = inputText[diffStart...].utf8

        sortCache.removeAll(keepingCapacity: true)

        for i in 0..<files.count {
            let score = scoreFuzzyMatch(haystack: files[i][diffStart...].utf8, needle: inputText)
            sortCache.append(SortFile(fileIndex: i, score: score))
        }

        sortCache.sort(by: compareFileScore)

        for i in 0..<min(maxResults, sortCache.count) {
            results.append(files[sortCache[i].fileIndex])
        }
    }

    func getAllFilesInDirectory(_ directory: String, maxDepth: Int) -> [String] {
        var files: [String] = []

        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(filePath: directory), includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return files
        }

        for case let fileUrl as URL in enumerator {
            files.append(fileUrl.path(percentEncoded: false))

            if fileUrl.hasDirectoryPath && enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
        }

        return files
    }

    func updateResultsNormal() {
        let path = getInputTextDirectory()
        let url = URL(filePath: String(path))

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

            if let aDotIndex = aDotIndex, let bDotIndex = bDotIndex {
                return aDotIndex < bDotIndex
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

    func close() {
        inputText = getResultBase()

        window?.close()
        app.hide(nil)
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
    let hotKey = HotKey(key: .space, modifiers: [.option])
    var window: Window?

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.activate()

        hotKey.keyDownHandler = {
            if let oldWindow = self.window.take() {
                oldWindow.close()
            }

            let window = Window(
                contentRect: NSRect(x: 0, y: 0, width: 768, height: 768 / 2),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered, defer: false)

            window.isReleasedWhenClosed = false

            self.view.mode = .Normal
            self.view.updateResults()

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true

            window.level = .floating

            window.contentView = self.view
            window.center()
            window.makeKeyAndOrderFront(self)

            self.window = window

            app.activate()
        }
    }
}

let delegate = Delegate()
app.delegate = delegate

app.run()
