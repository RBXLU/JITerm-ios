//
//  JITWaitView.swift
//  JITerm
//
//  Экран «нужен JIT». Приложение каждую секунду проверяет флаг CS_DEBUGGED
//  и само запускает Linux, как только JIT станет доступен.
//

import SwiftUI

struct JITWaitView: View {
    @EnvironmentObject private var vm: VirtualMachine
    @State private var showSettings = false
    @State private var stikError = false

    private var bundleID: String { Bundle.main.bundleIdentifier ?? "com.rbxlu.jiterm" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Включите JIT")
                            .font(.title.bold())
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Ожидание отладчика…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 24)

                Text("iOS запрещает приложениям генерировать машинный код. QEMU транслирует ARM-код Linux «на лету» (JIT), поэтому к JITerm нужно один раз за запуск подключить отладчик. Как только это произойдёт, Linux запустится автоматически.")
                    .font(.callout)

                Button {
                    openStikDebug()
                } label: {
                    Label("Включить через StikDebug", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if stikError {
                    Text("StikDebug не найден. Установите его (см. инструкцию ниже) или используйте другой способ.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                GroupBox("Способы включить JIT") {
                    VStack(alignment: .leading, spacing: 12) {
                        method("1. StikDebug (на самом iPhone)",
                               "Нажмите оранжевую кнопку выше — скрипт «legacy» выберется сам. Если включаете из StikDebug вручную, назначьте JITerm скрипт «legacy» (как для UTM). Нужны pairing-файл, Wi‑Fi и включённый LocalDevVPN.")
                        method("2. SideJITServer / JitStreamer (с компьютера)",
                               "С CachyOS: pipx install SideJITServer, затем SideJITServer --pair и запустите JIT для «\(bundleID)».")
                        method("3. Xcode (macOS)",
                               "Запустите приложение из Xcode с подключённым отладчиком.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Сведения для JIT-утилит") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Bundle ID", value: bundleID)
                        LabeledContent("PID", value: "\(ProcessInfo.processInfo.processIdentifier)")
                    }
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                }

                HStack {
                    Button {
                        vm.recheckJIT()
                    } label: {
                        Label("Проверить снова", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func method(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func openStikDebug() {
        // script-name=legacy: скрипт StikDebug, который обрабатывает brk #0x69 из QEMU
        // (сборка UTM) и подготавливает память под JIT на iOS 26+
        guard let url = URL(string: "stikjit://enable-jit?bundle-id=\(bundleID)&script-name=legacy") else { return }
        UIApplication.shared.open(url) { ok in
            stikError = !ok
        }
    }
}
