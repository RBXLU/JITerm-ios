//
//  DesktopScreen.swift
//  JITerm
//
//  Вкладка «Экран»: рабочий стол Linux (XFCE/LXQt/Openbox/i3 через VNC)
//  и панель клавиш. Пока рабочий стол не запущен — подсказка с кнопками.
//

import SwiftUI

struct DesktopScreen: View {
    @EnvironmentObject private var vm: VirtualMachine
    @ObservedObject var model: DesktopModel
    /// Отправить команду во вкладку терминала 1 и переключиться на неё.
    var runInTerminal: (String) -> Void

    @AppStorage("desktop.geometry") private var geometry = "1280x720"

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DesktopHostView(model: model)
                if !model.isConnected {
                    placeholder
                }
            }
            if model.isConnected {
                keyBar
            }
        }
        .background(Color.black)
        .onAppear { model.connect(port: vm.vncPort) }
        .onChange(of: vm.vncPort) { port in model.connect(port: port) }
    }

    // MARK: - Подсказка

    private var placeholder: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "display")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Рабочий стол не запущен")
                    .font(.title3.bold())
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    desktopButton("XFCE", "Привычный рабочий стол, тяжелее", "xfce")
                    desktopButton("LXQt", "Лёгкий рабочий стол на Qt", "lxqt")
                    desktopButton("Openbox", "Очень лёгкий: окна + панель", "openbox")
                    desktopButton("i3", "Плиточный WM, самый быстрый", "i3")
                }

                Picker("Разрешение", selection: $geometry) {
                    Text("1280×720").tag("1280x720")
                    Text("1024×576").tag("1024x576")
                    Text("1600×900").tag("1600x900")
                    Text("Портрет 720×1280").tag("720x1280")
                }
                .pickerStyle(.menu)

                Text("Первый запуск ставит пакеты из интернета — это может занять 5–20 минут, прогресс виден во вкладке 1. Под эмуляцией рабочий стол работает медленно: лучше всего — Openbox или i3.\n\nУправление: касание — клик, долгое нажатие — правая кнопка, ведение пальцем — перетаскивание, двумя пальцами — масштаб и прокрутка картинки.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground).opacity(0.97))
    }

    private var statusText: String {
        switch model.state {
        case .failed(let message): return message
        case .connected: return ""
        default:
            if !vm.state.isActive { return "Linux не запущен." }
            return "Запустите рабочий стол кнопкой ниже или командой jiterm-desktop в терминале. JITerm подключится к нему автоматически."
        }
    }

    private func desktopButton(_ title: String, _ subtitle: String, _ id: String) -> some View {
        Button {
            runInTerminal("jiterm-desktop \(id) \(geometry)")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.fill")
            }
            .padding(12)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!vm.state.isActive)
    }

    // MARK: - Панель клавиш

    private var keyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                barButton(systemImage: "keyboard") { model.view?.toggleKeyboard() }
                barButton("Esc") { model.tap(Keysym.escape) }
                barButton("Tab") { model.tap(Keysym.tab) }
                toggle("Ctrl", $model.ctrl)
                toggle("Alt", $model.alt)
                toggle("Shift", $model.shift)
                toggle("❖", $model.superKey)
                barButton(systemImage: "arrow.left") { model.tap(Keysym.left) }
                barButton(systemImage: "arrow.up") { model.tap(Keysym.up) }
                barButton(systemImage: "arrow.down") { model.tap(Keysym.down) }
                barButton(systemImage: "arrow.right") { model.tap(Keysym.right) }
                barButton(systemImage: "chevron.up.2") { model.scroll(up: true) }
                barButton(systemImage: "chevron.down.2") { model.scroll(up: false) }
                barButton(systemImage: "doc.on.clipboard") {
                    if let text = UIPasteboard.general.string { model.type(text) }
                }
                Menu {
                    ForEach(1...12, id: \.self) { n in
                        Button("F\(n)") { model.tap(Keysym.function(n)) }
                    }
                    Button("Delete") { model.tap(Keysym.delete) }
                    Button("Home") { model.tap(Keysym.home) }
                    Button("End") { model.tap(Keysym.end) }
                    Button("Ctrl+Alt+T (терминал)") { model.client?.tap(UInt32(Character("t").asciiValue!), modifiers: [Keysym.control, Keysym.alt]) }
                } label: {
                    Text("F…").font(.system(size: 14, weight: .semibold)).frame(minWidth: 36, minHeight: 32)
                        .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func barButton(_ title: String = "", systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(minWidth: 36, minHeight: 32)
            .padding(.horizontal, 4)
            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 40, minHeight: 32)
                .padding(.horizontal, 4)
                .background(binding.wrappedValue ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
