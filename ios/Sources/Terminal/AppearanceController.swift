//
//  AppearanceController.swift
//  JITerm
//
//  Применяет тему/шрифт/курсор ко всем вкладкам при изменении настроек.
//

import Combine
import SwiftUI
import UIKit

final class AppearanceController: ObservableObject {
    static let shared = AppearanceController()

    @Published private(set) var theme: TerminalTheme = .tokyoNight
    @Published private(set) var fontSize: CGFloat = SettingsDefaults.fontSize

    private var cancellables = Set<AnyCancellable>()
    private var lastSignature = ""

    private init() {
        SettingsDefaults.register()
        apply()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
    }

    func apply() {
        let d = UserDefaults.standard
        let theme = TerminalTheme(rawValue: d.string(forKey: SettingsKey.theme) ?? "") ?? .tokyoNight
        let size = CGFloat(min(32, max(7, d.double(forKey: SettingsKey.fontSize))))
        let fontKind = TerminalFont(rawValue: d.string(forKey: SettingsKey.fontName) ?? "") ?? .sfMono
        let cursor = CursorStyleOption(rawValue: d.string(forKey: SettingsKey.cursorStyle) ?? "") ?? .blinkBlock
        let optionMeta = d.bool(forKey: SettingsKey.optionAsMeta)
        if self.theme != theme { self.theme = theme }
        if self.fontSize != size { self.fontSize = size }
        VirtualMachine.shared.updateIdleTimer()
        // Применяем к терминалам только при реальном изменении (смена шрифта сбрасывает выделение)
        let signature = "\(theme.rawValue)|\(size)|\(fontKind.rawValue)|\(cursor.rawValue)|\(optionMeta)"
        guard signature != lastSignature else { return }
        lastSignature = signature
        let font = fontKind.font(size: size)
        for session in VirtualMachine.shared.sessions {
            session.applyAppearance(theme: theme, font: font, cursor: cursor, optionAsMeta: optionMeta)
        }
    }

    func adjustFontSize(by delta: CGFloat) {
        let current = UserDefaults.standard.double(forKey: SettingsKey.fontSize)
        let next = min(32, max(7, current + Double(delta)))
        UserDefaults.standard.set(next.rounded(), forKey: SettingsKey.fontSize)
    }
}
