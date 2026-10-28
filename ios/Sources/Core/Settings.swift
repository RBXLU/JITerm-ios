//
//  Settings.swift
//  JITerm
//

import SwiftUI
import UIKit

/// Все пользовательские настройки. Хранятся в UserDefaults через @AppStorage,
/// поэтому любые экраны, читающие тот же ключ, обновляются автоматически.
enum SettingsKey {
    static let fontSize = "terminal.fontSize"
    static let theme = "terminal.theme"
    static let cursorStyle = "terminal.cursorStyle"
    static let optionAsMeta = "terminal.optionAsMeta"
    static let hapticBell = "terminal.hapticBell"
    static let keepScreenOn = "terminal.keepScreenOn"
    static let backgroundMode = "vm.backgroundMode"
    static let bootDistro = "vm.bootDistro"

    static let memoryMB = "vm.memoryMB"
    static let cpuCount = "vm.cpuCount"
    static let jitCacheMB = "vm.jitCacheMB"
    static let cpuModel = "vm.cpuModel"
    static let verboseBoot = "vm.verboseBoot"
    static let autologin = "vm.autologin"
    static let extraKernelArgs = "vm.extraKernelArgs"
    static let portForwards = "vm.portForwards"
    static let autostart = "vm.autostart"
    static let sharedFolder = "vm.sharedFolder"
    static let lanAccess = "vm.lanAccess"
    static let fontName = "terminal.fontName"
}

enum SettingsDefaults {
    static let fontSize: Double = 13
    static let theme = TerminalTheme.tokyoNight.rawValue
    static let cursorStyle = CursorStyleOption.blinkBlock.rawValue
    static let memoryMB = 1024
    static let cpuCount = 2
    static let jitCacheMB = 256
    static let cpuModel = "cortex-a76"
    static let portForwards = "8000:8000"

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.fontSize: fontSize,
            SettingsKey.theme: theme,
            SettingsKey.cursorStyle: cursorStyle,
            SettingsKey.optionAsMeta: true,
            SettingsKey.hapticBell: true,
            SettingsKey.keepScreenOn: true,
            SettingsKey.backgroundMode: true,
            SettingsKey.bootDistro: "alpine",
            SettingsKey.memoryMB: memoryMB,
            SettingsKey.cpuCount: cpuCount,
            SettingsKey.jitCacheMB: jitCacheMB,
            SettingsKey.cpuModel: cpuModel,
            SettingsKey.verboseBoot: false,
            SettingsKey.autologin: true,
            SettingsKey.extraKernelArgs: "",
            SettingsKey.portForwards: portForwards,
            SettingsKey.autostart: true,
            SettingsKey.sharedFolder: true,
            SettingsKey.lanAccess: false,
            SettingsKey.fontName: TerminalFont.sfMono.rawValue,
        ])
    }
}

enum CursorStyleOption: String, CaseIterable, Identifiable {
    case blinkBlock, steadyBlock, blinkUnderline, steadyUnderline, blinkBar, steadyBar
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blinkBlock: return "Блок (мигает)"
        case .steadyBlock: return "Блок"
        case .blinkUnderline: return "Подчёркивание (мигает)"
        case .steadyUnderline: return "Подчёркивание"
        case .blinkBar: return "Черта (мигает)"
        case .steadyBar: return "Черта"
        }
    }
}

enum TerminalFont: String, CaseIterable, Identifiable {
    case sfMono, menlo, courier
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .courier: return "Courier New"
        }
    }

    func font(size: CGFloat) -> UIFont {
        switch self {
        case .sfMono: return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo: return UIFont(name: "Menlo-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .courier: return UIFont(name: "CourierNewPSMT", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

/// Снимок настроек ВМ на момент запуска.
struct VMConfiguration {
    var memoryMB: Int
    var cpuCount: Int
    var jitCacheMB: Int
    var cpuModel: String
    var verboseBoot: Bool
    var autologin: Bool
    var extraKernelArgs: String
    var portForwards: [PortForward]
    var sharedFolder: Bool
    var lanAccess: Bool

    static func current(_ d: UserDefaults = .standard) -> VMConfiguration {
        VMConfiguration(
            memoryMB: max(256, d.integer(forKey: SettingsKey.memoryMB)),
            cpuCount: min(8, max(1, d.integer(forKey: SettingsKey.cpuCount))),
            jitCacheMB: min(1024, max(32, d.integer(forKey: SettingsKey.jitCacheMB))),
            cpuModel: d.string(forKey: SettingsKey.cpuModel) ?? SettingsDefaults.cpuModel,
            verboseBoot: d.bool(forKey: SettingsKey.verboseBoot),
            autologin: d.bool(forKey: SettingsKey.autologin),
            extraKernelArgs: d.string(forKey: SettingsKey.extraKernelArgs) ?? "",
            portForwards: PortForward.parse(d.string(forKey: SettingsKey.portForwards) ?? ""),
            sharedFolder: d.bool(forKey: SettingsKey.sharedFolder),
            lanAccess: d.bool(forKey: SettingsKey.lanAccess)
        )
    }
}

/// Проброс TCP-порта: 127.0.0.1:host на iPhone → guest внутри Linux.
struct PortForward: Hashable {
    var host: UInt16
    var guest: UInt16

    /// Формат: "8000:8000, 2222:22" (или просто "8080" — тот же порт).
    static func parse(_ text: String) -> [PortForward] {
        text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" || $0 == "\n" })
            .compactMap { item -> PortForward? in
                let parts = item.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                switch parts.count {
                case 1:
                    guard let p = UInt16(parts[0]), p > 0 else { return nil }
                    return PortForward(host: p, guest: p)
                case 2:
                    guard let h = UInt16(parts[0]), let g = UInt16(parts[1]), h > 0, g > 0 else { return nil }
                    return PortForward(host: h, guest: g)
                default:
                    return nil
                }
            }
    }
}
