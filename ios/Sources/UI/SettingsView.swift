//
//  SettingsView.swift
//  JITerm
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: VirtualMachine

    // Терминал
    @AppStorage(SettingsKey.fontSize) private var fontSize = SettingsDefaults.fontSize
    @AppStorage(SettingsKey.fontName) private var fontName = TerminalFont.sfMono.rawValue
    @AppStorage(SettingsKey.theme) private var theme = SettingsDefaults.theme
    @AppStorage(SettingsKey.cursorStyle) private var cursorStyle = SettingsDefaults.cursorStyle
    @AppStorage(SettingsKey.optionAsMeta) private var optionAsMeta = true
    @AppStorage(SettingsKey.hapticBell) private var hapticBell = true
    @AppStorage(SettingsKey.keepScreenOn) private var keepScreenOn = true
    @AppStorage(SettingsKey.backgroundMode) private var backgroundMode = true

    // Система
    @AppStorage(SettingsKey.bootDistro) private var bootDistro = BootTarget.builtInID
    @AppStorage(SettingsKey.memoryMB) private var memoryMB = SettingsDefaults.memoryMB
    @AppStorage(SettingsKey.cpuCount) private var cpuCount = SettingsDefaults.cpuCount
    @AppStorage(SettingsKey.jitCacheMB) private var jitCacheMB = SettingsDefaults.jitCacheMB
    @AppStorage(SettingsKey.cpuModel) private var cpuModel = SettingsDefaults.cpuModel
    @AppStorage(SettingsKey.verboseBoot) private var verboseBoot = false
    @AppStorage(SettingsKey.autologin) private var autologin = true
    @AppStorage(SettingsKey.autostart) private var autostart = true
    @AppStorage(SettingsKey.extraKernelArgs) private var extraKernelArgs = ""
    @AppStorage(SettingsKey.portForwards) private var portForwards = SettingsDefaults.portForwards
    @AppStorage(SettingsKey.lanAccess) private var lanAccess = false
    @AppStorage(SettingsKey.sharedFolder) private var sharedFolder = true

    @State private var confirmReset = false
    @State private var resetDone = false
    @State private var errorText: String?
    @State private var installedDistros: [DistroInfo] = []
    @State private var distroToRemove: DistroInfo?

    private let memoryOptions = [512, 768, 1024, 1536, 2048, 3072, 4096]
    private let cacheOptions = [64, 128, 256, 512]
    private let cpuModels = [
        ("cortex-a76", "Cortex-A76 (рекомендуется)"),
        ("cortex-a72", "Cortex-A72 (быстрее, ARMv8.0)"),
        ("neoverse-n1", "Neoverse N1"),
        ("max", "max (все функции, медленнее)"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                terminalSection
                previewSection
                backgroundSection
                distroSection
                vmSection
                networkSection
                storageSection
                diagnosticsSection
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("О программе", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear { installedDistros = DistroCatalog.installed() }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: - Секции

    private var distroSection: some View {
        Section {
            Picker("Загружать", selection: $bootDistro) {
                Text("Alpine Linux (встроенный)").tag(BootTarget.builtInID)
                ForEach(installedDistros) { distro in
                    Text(distro.title).tag(distro.id)
                }
            }
            if let current = vm.bootTarget {
                LabeledContent("Сейчас запущен", value: current.title)
            }
            if let notice = vm.bootNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            ForEach(InstallableDistro.all) { distro in
                if let info = installedDistros.first(where: { $0.id == distro.id }) {
                    Button(role: .destructive) {
                        distroToRemove = info
                    } label: {
                        LabeledContent {
                            Text(ByteCountFormatter.string(fromByteCount: DistroCatalog.usageBytes(for: info.id), countStyle: .file))
                        } label: {
                            Label("Удалить \(info.title)", systemImage: "trash")
                        }
                    }
                    .disabled(vm.bootTarget?.id == info.id)
                } else {
                    Button {
                        install(distro)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Установить \(distro.title)", systemImage: "square.and.arrow.down")
                            Text(distro.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!canInstall)
                }
            }
        } header: {
            Text("Система")
        } footer: {
            Text(distroFooter)
        }
        .confirmationDialog("Удалить \(distroToRemove?.title ?? "")?",
                            isPresented: Binding(get: { distroToRemove != nil }, set: { if !$0 { distroToRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let distro = distroToRemove { removeDistro(distro) }
            }
        } message: {
            Text("Диск системы со всеми файлами будет удалён.")
        }
    }

    /// Ставить новые системы умеет только встроенный Alpine.
    private var canInstall: Bool {
        vm.state == .running && (vm.bootTarget?.isBuiltIn ?? false)
    }

    private var distroFooter: String {
        var text = "Debian и Arch ставятся из Alpine командой jiterm-install (нужен интернет, прогресс виден в терминале) и хранятся рядом с ним, Alpine не удаляется. Выбранная система загрузится при следующем запуске приложения."
        if !canInstall {
            text += " Установка доступна, когда запущен Alpine."
        }
        return text
    }

    private func install(_ distro: InstallableDistro) {
        // Показать первую консоль и выполнить установку в ней
        let defaults = UserDefaults.standard
        var tabs = (defaults.string(forKey: "ui.openTabs") ?? "0").split(separator: ",").map(String.init)
        if !tabs.contains("0") { tabs.insert("0", at: 0) }
        defaults.set(tabs.joined(separator: ","), forKey: "ui.openTabs")
        defaults.set(0, forKey: "ui.selectedTab")
        defaults.set(false, forKey: "ui.showDesktop")
        vm.sessions[0].send(text: "jiterm-install \(distro.id)\r")
        dismiss()
    }

    private func removeDistro(_ distro: DistroInfo) {
        do {
            try DistroCatalog.remove(distro.id)
        } catch {
            errorText = error.localizedDescription
        }
        installedDistros = DistroCatalog.installed()
        if !installedDistros.contains(where: { $0.id == bootDistro }) {
            bootDistro = BootTarget.builtInID
        }
    }

    private var terminalSection: some View {
        Section("Терминал") {
            Picker("Тема", selection: $theme) {
                ForEach(TerminalTheme.allCases) { t in
                    HStack {
                        ThemeSwatch(theme: t)
                        Text(t.title)
                    }
                    .tag(t.rawValue)
                }
            }
            Picker("Шрифт", selection: $fontName) {
                ForEach(TerminalFont.allCases) { f in Text(f.title).tag(f.rawValue) }
            }
            Stepper(value: $fontSize, in: 7...32, step: 1) {
                HStack {
                    Text("Размер шрифта")
                    Spacer()
                    Text("\(Int(fontSize)) pt").foregroundStyle(.secondary)
                }
            }
            Picker("Курсор", selection: $cursorStyle) {
                ForEach(CursorStyleOption.allCases) { c in Text(c.title).tag(c.rawValue) }
            }
            Toggle("Option как Meta (Alt)", isOn: $optionAsMeta)
            Toggle("Вибрация на сигнал (bell)", isOn: $hapticBell)
            Toggle("Не гасить экран", isOn: $keepScreenOn)
        }
    }

    private var backgroundSection: some View {
        Section {
            Toggle("Работать в фоне", isOn: $backgroundMode)
            if backgroundMode && BackgroundKeeper.shared.authorizationDenied {
                Button("Разрешить геолокацию в Настройках iOS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote)
            }
        } header: {
            Text("Фоновый режим")
        } footer: {
            Text("Linux продолжает работать, когда вы переключаетесь в другие приложения или блокируете экран. Для этого JITerm, как навигатор, держит включённой геолокацию с минимальной точностью: координаты не сохраняются и никуда не отправляются. Вверху экрана будет синий индикатор, расход батареи выше. iOS всё равно может закрыть приложение, если другим приложениям не хватит памяти — тогда уменьшите память ВМ до 768 МБ–1 ГБ.")
        }
    }

    private var previewSection: some View {
        Section {
            TerminalPreview(theme: TerminalTheme(rawValue: theme) ?? .tokyoNight,
                            font: (TerminalFont(rawValue: fontName) ?? .sfMono).font(size: CGFloat(fontSize)))
                .listRowInsets(EdgeInsets())
        } footer: {
            Text("Подсказка: размер шрифта меняется и щипком двумя пальцами прямо в терминале.")
        }
    }

    private var vmSection: some View {
        Section {
            Picker("Память", selection: $memoryMB) {
                ForEach(memoryOptions, id: \.self) { mb in
                    Text(mb >= 1024 ? String(format: "%.1f ГБ", Double(mb) / 1024) : "\(mb) МБ").tag(mb)
                }
            }
            Stepper(value: $cpuCount, in: 1...4) {
                HStack {
                    Text("Ядра CPU")
                    Spacer()
                    Text("\(cpuCount)").foregroundStyle(.secondary)
                }
            }
            Picker("Кэш JIT", selection: $jitCacheMB) {
                ForEach(cacheOptions, id: \.self) { mb in Text("\(mb) МБ").tag(mb) }
            }
            Picker("Модель CPU", selection: $cpuModel) {
                ForEach(cpuModels, id: \.0) { model in Text(model.1).tag(model.0) }
            }
            Toggle("Автозапуск при открытии", isOn: $autostart)
            Toggle("Автовход root", isOn: $autologin)
            Toggle("Подробный лог загрузки", isOn: $verboseBoot)
            VStack(alignment: .leading, spacing: 6) {
                Text("Параметры ядра")
                TextField("например: mitigations=off", text: $extraKernelArgs)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Виртуальная машина")
        } footer: {
            Text(vmFooter)
        }
    }

    private var vmFooter: String {
        var text = "iPhone ограничивает память приложений: больше 1–1,5 ГБ может привести к закрытию JITerm на устройствах с 4 ГБ ОЗУ."
        if vm.state.isActive {
            text = "Изменения применятся при следующем запуске приложения. " + text
        }
        return text
    }

    private var networkSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Проброс портов (iPhone:Linux)")
                TextField("8000:8000, 2222:22", text: $portForwards)
                    .font(.callout.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Toggle("Доступ из локальной сети", isOn: $lanAccess)
            if !vm.activeForwards.isEmpty {
                ForEach(vm.activeForwards, id: \.self) { fwd in
                    LabeledContent("localhost:\(String(fwd.host))", value: "→ Linux :\(String(fwd.guest))")
                        .font(.callout.monospaced())
                }
            }
            if !vm.skippedForwards.isEmpty {
                Text("Порты заняты и пропущены: " + vm.skippedForwards.map { String($0.host) }.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Сеть")
        } footer: {
            Text("Интернет внутри Linux работает через NAT. Проброс открывает сервер из Linux на iPhone: например, «python3 -m http.server 8000» будет доступен в Safari по адресу http://localhost:8000. С доступом из локальной сети к нему можно подключиться с компьютера (например, ssh после apk add openssh).")
        }
    }

    private var storageSection: some View {
        Section {
            Toggle("Общая папка (~/shared)", isOn: $sharedFolder)
            LabeledContent("Диск занимает", value: ByteCountFormatter.string(fromByteCount: GuestStorage.diskUsageBytes, countStyle: .file))
            if let info = GuestStorage.info {
                LabeledContent("Размер диска", value: info.diskSize)
            }
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label(resetDone ? "Система будет сброшена при запуске" : "Сбросить Linux к исходному состоянию",
                      systemImage: "arrow.counterclockwise")
            }
            .disabled(resetDone)
            .confirmationDialog("Удалить все данные Linux?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { resetDisk() }
            } message: {
                Text("Установленные пакеты и файлы внутри Linux будут удалены. Общая папка (~/shared) не затрагивается.")
            }
        } header: {
            Text("Хранилище")
        } footer: {
            Text("Общая папка видна в приложении «Файлы» → «На iPhone» → JITerm и внутри Linux как /root/shared.")
        }
    }

    private var diagnosticsSection: some View {
        Section("Диагностика") {
            LabeledContent("JIT") {
                Label(vm.jitEnabled ? "включён" : "выключен",
                      systemImage: vm.jitEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(vm.jitEnabled ? .green : .red)
            }
            if let duration = vm.bootDuration {
                LabeledContent("Загрузка заняла", value: String(format: "%.1f с", duration))
            }
            NavigationLink {
                LogView()
            } label: {
                Label("Журнал QEMU", systemImage: "doc.text.magnifyingglass")
            }
            if !vm.arguments.isEmpty {
                Button {
                    UIPasteboard.general.string = "qemu-system-aarch64 " + vm.arguments.joined(separator: " ")
                } label: {
                    Label("Скопировать команду QEMU", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func resetDisk() {
        do {
            if vm.state.isActive {
                // Диск используется — удалим его при выключении приложения через флаг
                UserDefaults.standard.set(true, forKey: GuestStorage.resetPendingKey)
                vm.powerOff()
            } else {
                try GuestStorage.resetDisk()
            }
            resetDone = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ThemeSwatch: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 0) {
            Color(theme.background)
            Color(theme.ansi[2])
            Color(theme.ansi[4])
            Color(theme.ansi[1])
        }
        .frame(width: 28, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4), lineWidth: 0.5))
    }
}

private struct TerminalPreview: View {
    let theme: TerminalTheme
    let font: UIFont

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line([("root@jiterm", 10), (":", -1), ("~", 12), ("# ", -1), ("python3 hello.py", -1)])
            line([("Привет из Alpine Linux!", 2)])
            line([("drwxr-xr-x ", -1), ("shared", 12), ("  ", -1), ("main.py", 11), ("  ", -1), ("notes.txt", -1)])
            line([("error: ", 9), ("файл не найден", 3)])
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(theme.background))
    }

    private func line(_ parts: [(String, Int)]) -> some View {
        parts.reduce(Text("")) { result, part in
            let color = part.1 < 0 ? theme.foreground : theme.ansi[part.1]
            return result + Text(part.0).foregroundColor(Color(color))
        }
        .font(Font(font as CTFont))
        .lineLimit(1)
    }
}
