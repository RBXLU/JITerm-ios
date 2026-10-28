//
//  DemoMode.swift
//  JITerm
//
//  Демо-режим для скриншотов в симуляторе (QEMU там не работает):
//  xcrun simctl launch booted com.rbxlu.jiterm -JITermDemo terminal
//  Режимы: jit, booting, terminal, settings, desktop, stopped, failed.
//

import Foundation

enum DemoMode: String {
    case jit, booting, terminal, settings, desktop, stopped, failed

    static var current: DemoMode? {
        UserDefaults.standard.string(forKey: "JITermDemo").flatMap(DemoMode.init(rawValue:))
    }
}

extension VirtualMachine {
    /// Текст, имитирующий сеанс работы, — для демонстрации отрисовки терминала.
    static let demoTranscript: String = {
        let g = "\u{1b}[1;32m", b = "\u{1b}[1;34m", c = "\u{1b}[36m", y = "\u{1b}[33m", m = "\u{1b}[35m"
        let r = "\u{1b}[0m", red = "\u{1b}[31m", bold = "\u{1b}[1m"
        let prompt = "\(g)root@jiterm\(r):\(b)~\(r)# "
        return [
            "",
            "  JITerm — Alpine Linux aarch64 на QEMU TCG (JIT)",
            "  Установлено: python3, pip, vim, nano, git, curl, tmux, htop, bash",
            "",
            "\(prompt)uname -sm && cat /etc/alpine-release",
            "Linux aarch64",
            "3.24.2",
            "\(prompt)python3 -c 'import sys; print(\"Привет из Python\", sys.version.split()[0])'",
            "Привет из Python 3.14.8",
            "\(prompt)ls -la",
            "total 28",
            "drwx------    5 root     root          4096 Oct 16 15:40 \(b).\(r)",
            "drwxr-xr-x   19 root     root          4096 Oct 16 14:52 \(b)..\(r)",
            "-rw-r--r--    1 root     root            52 Oct 16 14:52 .bashrc",
            "drwxr-xr-x    2 root     root             0 Oct 16 15:40 \(b)shared\(r)",
            "-rwxr-xr-x    1 root     root           211 Oct 16 15:41 \(g)hello.py\(r)",
            "\(prompt)apk add htop",
            "(1/1) Installing htop (3.4.1-r0)",
            "OK: 262 MiB in 153 packages",
            "\(prompt)git log --oneline -3",
            "\(y)869c42b\(r) \(c)(\(r)\(bold)\(c)HEAD -> \(g)main\(r)\(c))\(r) Add JITerm",
            "\(y)78cc694\(r) Initial commit",
            "\(prompt)echo -e '\\e[31mкрасный \\e[32mзелёный \\e[34mсиний \\e[35mпурпурный'",
            "\(red)красный \(g)зелёный \(b)синий \(m)пурпурный\(r)",
            prompt,
        ].joined(separator: "\r\n")
    }()

    func enterDemo(_ mode: DemoMode) {
        demoSetState(mode)
        sessions[0].terminalView.feed(text: Self.demoTranscript)
        sessions[1].terminalView.feed(text: "\r\n\u{1b}[1;32mroot@jiterm\u{1b}[0m:\u{1b}[1;34m~\u{1b}[0m# ")
    }
}
