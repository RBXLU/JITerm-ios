//
//  AboutView.swift
//  JITerm
//

import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("JITerm").font(.title.bold())
                    Text("Linux-терминал на iPhone и iPad").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Версии") {
                LabeledContent("Приложение", value: appVersion)
                if let info = GuestStorage.info {
                    LabeledContent("Alpine Linux", value: info.alpine)
                    LabeledContent("Ядро", value: info.kernel)
                    LabeledContent("Python", value: info.python)
                    LabeledContent("Образ собран", value: info.built)
                }
                LabeledContent("Эмулятор", value: "QEMU (сборка UTM), TCG JIT")
            }
            Section("Как это работает") {
                Text("QEMU эмулирует 64-битный ARM-компьютер (machine virt) и транслирует его код в нативный код iPhone с помощью JIT. Внутри работает обычный Alpine Linux с пакетным менеджером apk. Терминалы подключены к последовательным консолям ВМ.")
                    .font(.callout)
            }
            Section("Лицензии") {
                license("QEMU", "GNU GPL v2", "https://www.qemu.org/")
                license("UTM (сборка QEMU для iOS)", "Apache 2.0", "https://github.com/utmapp/UTM")
                license("SwiftTerm", "MIT", "https://github.com/migueldeicaza/SwiftTerm")
                license("Alpine Linux", "разные свободные лицензии", "https://alpinelinux.org/")
            }
        }
        .navigationTitle("О программе")
    }

    private func license(_ name: String, _ kind: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            LabeledContent(name, value: kind)
        }
    }
}
