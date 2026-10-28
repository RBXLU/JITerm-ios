//
//  VirtualMachine.swift
//  JITerm
//
//  Жизненный цикл Linux-ВМ: проверка JIT, подготовка диска, сборка аргументов
//  QEMU, запуск и подключение терминалов/канала управления.
//

import Combine
import Foundation
import UIKit

final class VirtualMachine: ObservableObject {
    enum State: Equatable {
        /// Ещё не запускали (автозапуск выключен).
        case idle
        /// Ждём, пока StikDebug/SideJITServer и т.п. подключат отладчик.
        case waitingForJIT
        /// QEMU запущен, Linux загружается.
        case booting
        /// Гостевой агент на связи — система загружена.
        case running
        /// QEMU завершился (выключение или ошибка).
        case stopped(message: String)
        /// Не удалось запустить QEMU.
        case failed(message: String)

        var isActive: Bool {
            self == .booting || self == .running
        }
    }

    static let shared = VirtualMachine()

    @Published private(set) var state: State = .idle
    @Published private(set) var jitEnabled: Bool = jt_jit_enabled()
    @Published private(set) var bootStartedAt: Date?
    @Published private(set) var bootDuration: TimeInterval?
    @Published private(set) var arguments: [String] = []
    @Published private(set) var activeForwards: [PortForward] = []
    @Published private(set) var skippedForwards: [PortForward] = []
    /// Какая система загружена (Alpine или установленная через jiterm-install).
    @Published private(set) var bootTarget: BootTarget?
    /// Порт на 127.0.0.1 iPhone, проброшенный на VNC рабочего стола (гость :5901).
    @Published private(set) var vncPort: UInt16?
    /// Сообщение, если выбранную систему загрузить не удалось и загрузился Alpine.
    @Published private(set) var bootNotice: String?

    /// 4 консоли: системная (ttyAMA0) + 3 virtio (hvc0..hvc2).
    let sessions: [TerminalSession] = [
        TerminalSession(id: 0, title: "1", device: "ttyAMA0"),
        TerminalSession(id: 1, title: "2", device: "hvc0"),
        TerminalSession(id: 2, title: "3", device: "hvc1"),
        TerminalSession(id: 3, title: "4", device: "hvc2"),
    ]

    private var control: LoopbackLink?
    private var qmp: LoopbackLink?
    private var jitTimer: Timer?
    private var stuckCPUReports = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {
        for session in sessions {
            session.onResize = { [weak self] s in self?.sendResize(s) }
        }
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.control?.send("sync\n") }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.syncGuest() }
            .store(in: &cancellables)
    }

    // MARK: - Запуск

    /// Запускает ВМ (или ожидание JIT). Повторные вызовы безопасны.
    func start() {
        switch state {
        case .booting, .running, .stopped, .failed:
            return
        case .idle, .waitingForJIT:
            break
        }
        guard !jt_qemu_was_started() else {
            state = .stopped(message: "QEMU уже работал в этом процессе. Закройте приложение полностью и откройте снова.")
            return
        }
        jitEnabled = jt_jit_enabled()
        guard jitEnabled else {
            state = .waitingForJIT
            startJITPolling()
            return
        }
        stopJITPolling()
        state = .booting
        bootStartedAt = Date()

        let config = VMConfiguration.current()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try GuestStorage.prepare()
                DistroCatalog.excludeFromBackup()
                let wanted = UserDefaults.standard.string(forKey: SettingsKey.bootDistro) ?? BootTarget.builtInID
                var notice: String?
                var target = DistroCatalog.bootTarget(for: wanted)
                if target == nil {
                    notice = "Система «\(wanted)» не найдена — загружен встроенный Alpine."
                    target = .builtIn
                }
                DispatchQueue.main.async {
                    self.bootNotice = notice
                    self.launch(config, target: target!)
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    private func launch(_ config: VMConfiguration, target: BootTarget) {
        let ports = PortAllocator.freePorts(sessions.count + 3)
        guard ports.count == sessions.count + 3 else {
            state = .failed(message: "Не удалось выделить локальные порты для консолей.")
            return
        }
        let consolePorts = Array(ports[0..<sessions.count])
        let controlPort = ports[sessions.count]
        let qmpPort = ports[sessions.count + 1]
        let vncPort = ports[sessions.count + 2]
        bootTarget = target
        self.vncPort = vncPort

        // Проброс портов: занятые порты пропускаем, иначе QEMU не стартует
        let lanAccess = config.lanAccess
        var forwards: [PortForward] = []
        var skipped: [PortForward] = []
        for fwd in config.portForwards where !forwards.contains(where: { $0.host == fwd.host }) {
            if PortAllocator.isFree(fwd.host, anyAddress: lanAccess) && !ports.contains(fwd.host) {
                forwards.append(fwd)
            } else {
                skipped.append(fwd)
            }
        }
        activeForwards = forwards
        skippedForwards = skipped

        let args = QemuArguments.build(config: config,
                                       target: target,
                                       vncPort: vncPort,
                                       consolePorts: consolePorts,
                                       controlPort: controlPort,
                                       qmpPort: qmpPort,
                                       forwards: forwards,
                                       lanAccess: lanAccess)
        arguments = args

        _ = jt_redirect_stdio(GuestStorage.logURL.path)
        print("JITerm: starting QEMU (\(target.title))\n" + args.joined(separator: " "))

        let argv: [UnsafeMutablePointer<CChar>?] = (["qemu-system-aarch64"] + args).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        var errbuf = [CChar](repeating: 0, count: 1024)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let result = argv.map { UnsafePointer($0) }.withUnsafeBufferPointer { buf -> Int32 in
            jt_qemu_start(GuestStorage.qemuLibraryURL.path, Int32(buf.count), buf.baseAddress,
                          { status, ctx in
                              guard let ctx else { return }
                              let vm = Unmanaged<VirtualMachine>.fromOpaque(ctx).takeUnretainedValue()
                              DispatchQueue.main.async { vm.qemuDidExit(status: status) }
                          }, ctx, &errbuf, errbuf.count)
        }
        guard result == 0 else {
            state = .failed(message: "Не удалось загрузить QEMU: " + String(cString: errbuf))
            return
        }

        for (session, port) in zip(sessions, consolePorts) {
            session.connect(port: port)
        }

        let control = LoopbackLink(name: "control", port: controlPort)
        control.onStateChange = { [weak self] linkState in
            if linkState == .connected { self?.syncGuest() }
        }
        control.onData = { [weak self] data in self?.handleControl(data) }
        self.control = control
        control.start()

        let qmp = LoopbackLink(name: "qmp", port: qmpPort)
        // Ответы QMP пишем в журнал: по ним видно, работает ли ВМ
        qmp.onData = { [weak self] data in
            guard let text = String(data: data, encoding: .utf8) else { return }
            if text.contains("PC=") {
                // Ответ на «info registers»: оставляем только адреса команд всех CPU
                let pcs = text.components(separatedBy: CharacterSet(charactersIn: " \\n\"")).filter { $0.hasPrefix("PC=") }
                print("JITerm QMP: CPU " + pcs.joined(separator: " "))
                self?.checkCPUProgress(pcs)
            } else {
                print("JITerm QMP: " + text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        qmp.send("{\"execute\":\"qmp_capabilities\"}\n{\"execute\":\"query-status\"}\n")
        self.qmp = qmp
        qmp.start()
        scheduleBootDiagnostics(round: 1)

        updateIdleTimer()
    }

    /// Пока Linux грузится, раз в 20 с пишем в журнал состояние ВМ и адреса PC
    /// процессоров — по ним видно, идёт ли эмуляция или всё стоит.
    private func scheduleBootDiagnostics(round: Int) {
        guard round <= 15 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.state == .booting else { return }
            print("JITerm: диагностика загрузки, \(round * 20) с")
            self.qmp?.send("{\"execute\":\"query-status\"}\n")
            self.qmp?.send("{\"execute\":\"human-monitor-command\",\"arguments\":{\"command-line\":\"info registers\"}}\n")
            self.scheduleBootDiagnostics(round: round + 1)
        }
    }

    /// Если процессор ВМ так и стоит на первой инструкции (адрес загрузчика
    /// 0x40000000), значит iOS не даёт выполнять JIT-код: на iOS 26+ память
    /// под JIT должен подготовить отладчик (скрипт «legacy» в StikDebug).
    private func checkCPUProgress(_ pcs: [String]) {
        guard state == .booting else { return }
        let stuck = !pcs.isEmpty && pcs.allSatisfy { $0 == "PC=0000000040000000" }
        stuckCPUReports = stuck ? stuckCPUReports + 1 : 0
        guard stuckCPUReports >= 2 else { return }
        print("JITerm: процессор ВМ не выполняет код — JIT-память не подготовлена")
        state = .failed(message: """
        JIT включился, но iOS не разрешила выполнять сгенерированный код — процессор Linux стоит на месте.

        На iOS 26 и новее память под JIT должен подготовить StikDebug скриптом «legacy». \
        Закройте JITerm полностью, откройте снова и нажмите «Включить через StikDebug» \
        (кнопка сама выбирает этот скрипт). Если включаете JIT из самого StikDebug — \
        назначьте JITerm скрипт «legacy».
        """)
        updateIdleTimer()
    }

    /// Сообщения от гостевого агента.
    private func handleControl(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) where line.trimmingCharacters(in: .whitespaces) == "ready" {
            if state == .booting {
                state = .running
                if let start = bootStartedAt {
                    bootDuration = Date().timeIntervalSince(start)
                }
            }
            syncGuest()
        }
    }

    private func qemuDidExit(status: Int32) {
        control?.stop()
        qmp?.stop()
        for session in sessions {
            session.disconnect()
        }
        let message: String
        if status == 0 {
            message = "Linux выключен. Чтобы запустить его снова, закройте приложение и откройте заново."
        } else {
            message = "QEMU завершился с ошибкой (код \(status)). Подробности — в журнале QEMU."
        }
        state = .stopped(message: message)
        updateIdleTimer()
    }

    // MARK: - JIT

    private func startJITPolling() {
        guard jitTimer == nil else { return }
        jitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if jt_jit_enabled() {
                self.jitEnabled = true
                self.stopJITPolling()
                self.start()
            }
        }
    }

    private func stopJITPolling() {
        jitTimer?.invalidate()
        jitTimer = nil
    }

    /// Только для демо-режима (скриншоты в симуляторе).
    func demoSetState(_ mode: DemoMode) {
        switch mode {
        case .jit: state = .waitingForJIT
        case .booting: state = .booting; bootStartedAt = Date().addingTimeInterval(-12)
        case .terminal, .settings, .desktop: state = .running; bootDuration = 18.4; bootTarget = .builtIn
        case .stopped: state = .stopped(message: "Linux выключен. Чтобы запустить его снова, закройте приложение и откройте заново.")
        case .failed: state = .failed(message: "Не удалось загрузить QEMU: пример сообщения об ошибке.")
        }
        jitEnabled = mode != .jit
    }

    func recheckJIT() {
        jitEnabled = jt_jit_enabled()
        if jitEnabled, state == .waitingForJIT {
            start()
        }
    }

    // MARK: - Управление гостем

    private func sendResize(_ session: TerminalSession) {
        guard session.cols > 0, session.rows > 0 else { return }
        control?.send("resize \(session.device) \(session.rows) \(session.cols)\n")
    }

    /// Синхронизация часов и размеров всех консолей (после загрузки и выхода из фона).
    func syncGuest() {
        guard state.isActive else { return }
        control?.send("time \(Int(Date().timeIntervalSince1970))\n")
        sessions.forEach(sendResize)
    }

    func reboot() {
        control?.send("sync\nreboot\n")
    }

    func powerOff() {
        control?.send("sync\npoweroff\n")
    }

    /// Аппаратный сброс через QMP (если система зависла).
    func hardReset() {
        qmp?.send("{\"execute\":\"system_reset\"}\n")
    }

    /// Мгновенное выключение через QMP (как выдернуть шнур).
    func forceQuit() {
        qmp?.send("{\"execute\":\"quit\"}\n")
    }

    func updateIdleTimer() {
        let keepOn = UserDefaults.standard.bool(forKey: SettingsKey.keepScreenOn)
        UIApplication.shared.isIdleTimerDisabled = keepOn && state.isActive
        BackgroundKeeper.shared.update(vmActive: state.isActive)
    }
}

// MARK: - Аргументы QEMU

enum QemuArguments {
    static func kernelCommandLine(_ config: VMConfiguration, target: BootTarget) -> String {
        var parts = [target.baseCmdline]
        if !config.verboseBoot {
            parts += ["quiet", "loglevel=3"]
        }
        if !config.autologin && target.isBuiltIn {
            parts.append("jiterm.noautologin")
        }
        let extra = config.extraKernelArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            parts.append(extra)
        }
        return parts.joined(separator: " ")
    }

    static func build(config: VMConfiguration,
                      target: BootTarget,
                      vncPort: UInt16,
                      consolePorts: [UInt16],
                      controlPort: UInt16,
                      qmpPort: UInt16,
                      forwards: [PortForward],
                      lanAccess: Bool) -> [String] {
        func socket(_ id: String, _ port: UInt16) -> String {
            "socket,id=\(id),host=127.0.0.1,port=\(port),server=on,wait=off,nodelay=on"
        }
        let bindAddress = lanAccess ? "" : "127.0.0.1"
        // VNC рабочего стола (jiterm-desktop → Xvnc :1) — только для самого iPhone
        let hostfwd = forwards.map { ",hostfwd=tcp:\(bindAddress):\($0.host)-:\($0.guest)" }.joined()
            + ",hostfwd=tcp:127.0.0.1:\(vncPort)-:5901"

        var args: [String] = [
            "-nodefaults",
            "-display", "none",
            "-monitor", "none",
            "-machine", "virt",
            "-cpu", config.cpuModel,
            // split-wx: на iOS без entitlement'а JIT-память отображается дважды (RW + RX)
            "-accel", "tcg,thread=multi,tb-size=\(config.jitCacheMB),split-wx=on",
            "-smp", "\(config.cpuCount)",
            "-m", "\(config.memoryMB)",
            "-kernel", target.kernel.path,
            "-initrd", target.initrd.path,
            "-append", kernelCommandLine(config, target: target),
            "-drive", "file=\(target.disk.path),if=none,id=hd0,format=\(target.diskFormat),discard=unmap,detect-zeroes=unmap",
            "-device", "virtio-blk-pci,drive=hd0",
            "-netdev", "user,id=net0\(hostfwd)",
            "-device", "virtio-net-pci,netdev=net0,romfile=",
            "-device", "virtio-rng-pci",
            "-chardev", socket("con0", consolePorts[0]),
            "-serial", "chardev:con0",
            "-device", "virtio-serial-pci,id=vser0",
        ]
        for (index, port) in consolePorts.dropFirst().enumerated() {
            let id = "hvc\(index)"
            args += ["-chardev", socket(id, port), "-device", "virtconsole,bus=vser0.0,chardev=\(id)"]
        }
        args += [
            "-chardev", socket("ctl", controlPort),
            "-device", "virtserialport,bus=vser0.0,chardev=ctl,name=jiterm.control",
            "-qmp", "tcp:127.0.0.1:\(qmpPort),server=on,wait=off",
        ]
        if config.sharedFolder {
            args += [
                "-fsdev", "local,id=fs0,path=\(GuestStorage.sharedURL.path),security_model=none",
                "-device", "virtio-9p-pci,fsdev=fs0,mount_tag=jiterm",
            ]
        }
        return args
    }
}
