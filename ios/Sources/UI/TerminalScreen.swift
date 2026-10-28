//
//  TerminalScreen.swift
//  JITerm
//
//  Главный экран: вкладки, терминал, меню действий и статус загрузки.
//

import SwiftUI

struct TerminalScreen: View {
    @EnvironmentObject private var vm: VirtualMachine
    @EnvironmentObject private var appearance: AppearanceController

    @AppStorage("ui.openTabs") private var openTabsRaw = "0"
    @AppStorage("ui.selectedTab") private var selectedTab = 0
    @AppStorage("ui.showDesktop") private var showDesktop = false

    @State private var showSettings = false
    @State private var showLog = false
    @State private var focusToken = 0
    @State private var confirmPowerOff = false

    private var openTabs: [Int] {
        let ids = openTabsRaw.split(separator: ",").compactMap { Int($0) }.filter { $0 >= 0 && $0 < vm.sessions.count }
        return ids.isEmpty ? [0] : Array(Set(ids)).sorted()
    }

    /// Терминал получает фокус, только когда поверх него ничего не открыто.
    private var terminalActive: Bool {
        guard !showSettings && !showLog && !confirmPowerOff && !showDesktop else { return false }
        switch vm.state {
        case .stopped, .failed: return false
        default: return true
        }
    }

    private var currentSession: TerminalSession {
        let id = openTabs.contains(selectedTab) ? selectedTab : openTabs[0]
        return vm.sessions[id]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .top) {
                TerminalHostView(session: currentSession,
                                 background: appearance.theme.background,
                                 focusToken: focusToken,
                                 isActive: terminalActive)
                    .ignoresSafeArea(.keyboard)
                if showDesktop {
                    DesktopScreen(model: DesktopModel.shared, runInTerminal: runInTerminal)
                }
                if vm.state == .booting {
                    BootBanner()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .background(Color(appearance.theme.background).ignoresSafeArea())
        .overlay { stoppedOverlay }
        .animation(.easeInOut(duration: 0.25), value: vm.state)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            if DemoMode.current == .settings { showSettings = true }
        }
        .onChange(of: vm.state) { state in
            if case .stopped = state { DesktopModel.shared.disconnect() }
            if case .failed = state { DesktopModel.shared.disconnect() }
        }
        .sheet(isPresented: $showLog) { NavigationStack { LogView() } }
        .confirmationDialog("Выключить Linux?", isPresented: $confirmPowerOff, titleVisibility: .visible) {
            Button("Выключить", role: .destructive) { vm.powerOff() }
        } message: {
            Text("После выключения для нового запуска нужно перезапустить приложение.")
        }
    }

    // MARK: - Верхняя панель

    private var topBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(openTabs, id: \.self) { id in
                        TabChip(session: vm.sessions[id],
                                index: id + 1,
                                selected: !showDesktop && id == currentSession.id,
                                closable: openTabs.count > 1,
                                onSelect: { select(id) },
                                onClose: { closeTab(id) })
                    }
                    DesktopChip(selected: showDesktop) {
                        showDesktop = true
                    }
                    if openTabs.count < vm.sessions.count {
                        Button {
                            addTab()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityLabel("Новая вкладка")
                    }
                }
                .padding(.vertical, 6)
            }
            StatusDot(state: vm.state)
            actionsMenu
        }
        .padding(.horizontal, 10)
        .foregroundStyle(Color(appearance.theme.foreground))
        .background(Color(appearance.theme.background).opacity(0.96))
    }

    private var actionsMenu: some View {
        Menu {
            Section {
                Button { currentSession.paste() } label: { Label("Вставить", systemImage: "doc.on.clipboard") }
                Button { currentSession.send(bytes: [0x03]) } label: { Label("Ctrl-C", systemImage: "xmark.octagon") }
                Button { currentSession.send(bytes: [0x04]) } label: { Label("Ctrl-D (выход)", systemImage: "arrow.uturn.left") }
                Button { currentSession.send(bytes: [0x0c]) } label: { Label("Очистить экран", systemImage: "eraser") }
            }
            Section {
                Button { appearance.adjustFontSize(by: 1) } label: { Label("Крупнее", systemImage: "textformat.size.larger") }
                Button { appearance.adjustFontSize(by: -1) } label: { Label("Мельче", systemImage: "textformat.size.smaller") }
                Button { vm.syncGuest() } label: { Label("Обновить размер окна", systemImage: "arrow.up.left.and.arrow.down.right") }
            }
            Section("Система") {
                Button { vm.reboot() } label: { Label("Перезагрузить", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { confirmPowerOff = true } label: { Label("Выключить", systemImage: "power") }
                Menu("Аварийно") {
                    Button { vm.hardReset() } label: { Label("Сброс (reset)", systemImage: "bolt.trianglebadge.exclamationmark") }
                    Button(role: .destructive) { vm.forceQuit() } label: { Label("Остановить QEMU", systemImage: "stop.fill") }
                }
            }
            Section {
                Button { showLog = true } label: { Label("Журнал QEMU", systemImage: "doc.text.magnifyingglass") }
                Button { showSettings = true } label: { Label("Настройки", systemImage: "gearshape") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel("Действия")
    }

    // MARK: - Оверлей «выключено»

    @ViewBuilder private var stoppedOverlay: some View {
        switch vm.state {
        case .stopped(let message), .failed(let message):
            let failed: Bool = {
                if case .failed = vm.state { return true }
                return false
            }()
            VStack(spacing: 16) {
                Image(systemName: failed ? "exclamationmark.triangle.fill" : "power.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(failed ? .red : .secondary)
                Text(failed ? "Не удалось запустить" : "Система остановлена")
                    .font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Журнал QEMU") { showLog = true }
                        .buttonStyle(.bordered)
                    Button("Настройки") { showSettings = true }
                        .buttonStyle(.bordered)
                }
                Button(role: .destructive) {
                    exit(0)
                } label: {
                    Label("Закрыть приложение", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        default:
            EmptyView()
        }
    }

    // MARK: - Вкладки

    private func select(_ id: Int) {
        selectedTab = id
        showDesktop = false
        focusToken += 1
    }

    /// Команда из вкладки «Экран»: выполнить в первой консоли и показать её.
    private func runInTerminal(_ command: String) {
        let id = openTabs[0]
        vm.sessions[id].send(text: command + "\r")
        select(id)
    }

    private func addTab() {
        guard let next = (0..<vm.sessions.count).first(where: { !openTabs.contains($0) }) else { return }
        openTabsRaw = (openTabs + [next]).map(String.init).joined(separator: ",")
        select(next)
        // Разбудить getty в новой консоли
        vm.sessions[next].send(text: "\r")
    }

    private func closeTab(_ id: Int) {
        let remaining = openTabs.filter { $0 != id }
        guard !remaining.isEmpty else { return }
        openTabsRaw = remaining.map(String.init).joined(separator: ",")
        if selectedTab == id {
            select(remaining.last ?? 0)
        }
    }
}

// MARK: - Компоненты

private struct TabChip: View {
    @ObservedObject var session: TerminalSession
    let index: Int
    let selected: Bool
    let closable: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 140)
            if closable && selected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть вкладку")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var label: String {
        session.title == session.defaultTitle ? "\(index) · \(session.device)" : "\(index) · \(session.title)"
    }
}

private struct DesktopChip: View {
    @ObservedObject private var model = DesktopModel.shared
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "display")
                .font(.system(size: 11, weight: .semibold))
            Text("Экран")
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
            if model.isConnected {
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityLabel("Рабочий стол")
    }
}

private struct StatusDot: View {
    let state: VirtualMachine.State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .booting: return .orange
        case .failed: return .red
        default: return .gray
        }
    }

    private var label: String {
        switch state {
        case .running: return "Linux работает"
        case .booting: return "Загрузка"
        case .failed: return "Ошибка"
        default: return "Остановлено"
        }
    }
}

private struct BootBanner: View {
    @EnvironmentObject private var vm: VirtualMachine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Загрузка Linux…").font(.subheadline.bold())
                    if let start = vm.bootStartedAt {
                        Text("\(Int(context.date.timeIntervalSince(start))) с · первый запуск дольше")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
        }
    }
}
