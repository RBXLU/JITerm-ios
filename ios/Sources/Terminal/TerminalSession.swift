//
//  TerminalSession.swift
//  JITerm
//
//  Одна вкладка терминала: экземпляр SwiftTerm.TerminalView + TCP-канал
//  к соответствующей консоли QEMU (ttyAMA0 или hvc0..hvc2).
//

import SwiftTerm
import UIKit

final class TerminalSession: NSObject, ObservableObject, Identifiable {
    let id: Int
    /// Имя tty внутри Linux.
    let device: String
    let defaultTitle: String

    @Published private(set) var title: String
    @Published private(set) var isConnected = false
    @Published private(set) var hasOutput = false

    let terminalView: TerminalView
    private(set) var cols = 0
    private(set) var rows = 0

    /// Вызывается при изменении размера окна (для отправки в гостевую систему).
    var onResize: ((TerminalSession) -> Void)?
    /// Вызывается при первом выводе в этой консоли.
    var onFirstOutput: ((TerminalSession) -> Void)?

    private var link: LoopbackLink?

    init(id: Int, title: String, device: String) {
        self.id = id
        self.device = device
        self.defaultTitle = title
        self.title = title
        self.terminalView = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), font: nil)
        super.init()
        terminalView.terminalDelegate = self
    }

    func connect(port: UInt16) {
        link?.stop()
        let link = LoopbackLink(name: device, port: port)
        link.onData = { [weak self] data in
            guard let self else { return }
            self.terminalView.feed(byteArray: ArraySlice([UInt8](data)))
            if !self.hasOutput {
                self.hasOutput = true
                self.onFirstOutput?(self)
            }
        }
        link.onStateChange = { [weak self] state in
            self?.isConnected = (state == .connected)
        }
        self.link = link
        link.start()
    }

    func disconnect() {
        link?.stop()
        link = nil
        isConnected = false
    }

    /// Отправить текст в консоль так, как будто его набрали.
    func send(text: String) {
        link?.send(text)
    }

    func send(bytes: [UInt8]) {
        link?.send(Data(bytes))
    }

    func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        // Bracketed paste, если программа его включила (bash, vim)
        if terminalView.getTerminal().bracketedPasteMode {
            send(text: "\u{1b}[200~" + text + "\u{1b}[201~")
        } else {
            send(text: text.replacingOccurrences(of: "\n", with: "\r"))
        }
    }

    func applyAppearance(theme: TerminalTheme, font: UIFont, cursor: CursorStyleOption, optionAsMeta: Bool) {
        terminalView.font = font
        terminalView.installColors(theme.ansiColors)
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.nativeBackgroundColor = theme.background
        terminalView.backgroundColor = theme.background
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selection
        terminalView.keyboardAppearance = theme.isLight ? .light : .dark
        terminalView.optionAsMetaKey = optionAsMeta
        terminalView.getTerminal().setCursorStyle(cursor.swiftTermStyle)
        terminalView.setNeedsDisplay()
    }
}

extension TerminalSession: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        link?.send(Data(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0, newCols != cols || newRows != rows else { return }
        cols = newCols
        rows = newRows
        onResize?(self)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? defaultTitle : trimmed
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }

    func bell(source: TerminalView) {
        if UserDefaults.standard.bool(forKey: SettingsKey.hapticBell) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let text = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = text
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

extension CursorStyleOption {
    var swiftTermStyle: CursorStyle {
        switch self {
        case .blinkBlock: return .blinkBlock
        case .steadyBlock: return .steadyBlock
        case .blinkUnderline: return .blinkUnderline
        case .steadyUnderline: return .steadyUnderline
        case .blinkBar: return .blinkBar
        case .steadyBar: return .steadyBar
        }
    }
}
