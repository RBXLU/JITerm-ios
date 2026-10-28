//
//  Themes.swift
//  JITerm
//

import SwiftTerm
import UIKit

enum TerminalTheme: String, CaseIterable, Identifiable {
    case tokyoNight, dracula, gruvbox, nord, solarizedDark, oneDark, matrix, solarizedLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokyoNight: return "Tokyo Night"
        case .dracula: return "Dracula"
        case .gruvbox: return "Gruvbox"
        case .nord: return "Nord"
        case .solarizedDark: return "Solarized Dark"
        case .oneDark: return "One Dark"
        case .matrix: return "Matrix"
        case .solarizedLight: return "Solarized Light"
        }
    }

    var isLight: Bool { self == .solarizedLight }

    /// background, foreground, cursor, selection, затем 16 цветов ANSI.
    private var hex: (bg: UInt32, fg: UInt32, cursor: UInt32, selection: UInt32, ansi: [UInt32]) {
        switch self {
        case .tokyoNight:
            return (0x1a1b26, 0xc0caf5, 0xc0caf5, 0x33467c,
                    [0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
                     0x414868, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xc0caf5])
        case .dracula:
            return (0x282a36, 0xf8f8f2, 0xf8f8f2, 0x44475a,
                    [0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
                     0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff])
        case .gruvbox:
            return (0x282828, 0xebdbb2, 0xebdbb2, 0x504945,
                    [0x282828, 0xcc241d, 0x98971a, 0xd79921, 0x458588, 0xb16286, 0x689d6a, 0xa89984,
                     0x928374, 0xfb4934, 0xb8bb26, 0xfabd2f, 0x83a598, 0xd3869b, 0x8ec07c, 0xebdbb2])
        case .nord:
            return (0x2e3440, 0xd8dee9, 0xd8dee9, 0x434c5e,
                    [0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0,
                     0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4])
        case .solarizedDark:
            return (0x002b36, 0x839496, 0x93a1a1, 0x073642,
                    [0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5,
                     0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3])
        case .oneDark:
            return (0x282c34, 0xabb2bf, 0x528bff, 0x3e4451,
                    [0x282c34, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xabb2bf,
                     0x5c6370, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xffffff])
        case .matrix:
            return (0x000000, 0x33ff66, 0x33ff66, 0x0f3d1f,
                    [0x000000, 0x1f8f3a, 0x33ff66, 0x8cff9e, 0x1aa34a, 0x2ecc71, 0x66ffaa, 0xb3ffcc,
                     0x0d4d1f, 0x2ebf55, 0x66ff8c, 0xccffd6, 0x33cc66, 0x55e68a, 0x99ffc2, 0xe6fff0])
        case .solarizedLight:
            return (0xfdf6e3, 0x657b83, 0x586e75, 0xeee8d5,
                    [0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5,
                     0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3])
        }
    }

    var background: UIColor { UIColor(hex: hex.bg) }
    var foreground: UIColor { UIColor(hex: hex.fg) }
    var cursor: UIColor { UIColor(hex: hex.cursor) }
    var selection: UIColor { UIColor(hex: hex.selection).withAlphaComponent(0.8) }
    var ansi: [UIColor] { hex.ansi.map { UIColor(hex: $0) } }

    var ansiColors: [SwiftTerm.Color] {
        hex.ansi.map { value in
            let r = UInt16((value >> 16) & 0xff), g = UInt16((value >> 8) & 0xff), b = UInt16(value & 0xff)
            return SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }
}
