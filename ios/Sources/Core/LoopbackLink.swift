//
//  LoopbackLink.swift
//  JITerm
//
//  TCP-клиент к сокетам QEMU на 127.0.0.1 (консоли, канал управления, QMP).
//  QEMU слушает с server=on,wait=off, поэтому до старта ВМ соединение
//  отклоняется — LoopbackLink сам переподключается, пока его не остановят.
//
//  Используются обычные BSD-сокеты (а не Network.framework): так соединение
//  с 127.0.0.1 не зависит от VPN (LocalDevVPN) и политик выбора интерфейса.
//

import Foundation

final class LoopbackLink {
    enum State: Equatable {
        case idle, connecting, connected, closed
    }

    let port: UInt16
    let name: String

    /// Вызываются на главной очереди.
    var onData: ((Data) -> Void)?
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle

    private let lock = NSLock()
    private let writeQueue: DispatchQueue
    private var fd: Int32 = -1
    private var stopped = false
    private var pending = Data()
    private var thread: Thread?

    init(name: String, port: UInt16) {
        self.name = name
        self.port = port
        self.writeQueue = DispatchQueue(label: "jiterm.link.\(name).write", qos: .userInteractive)
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard thread == nil else { return }
        stopped = false
        let t = Thread { [weak self] in self?.run() }
        t.name = "jiterm.link.\(name)"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        lock.lock()
        stopped = true
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
        }
        lock.unlock()
    }

    /// Отправка данных. Пока соединения нет, данные копятся (до 64 КБ).
    func send(_ data: Data) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let fd = self.fd
            if fd < 0 {
                if self.pending.count < 64 * 1024 {
                    self.pending.append(data)
                }
                self.lock.unlock()
                return
            }
            self.lock.unlock()
            Self.writeAll(fd, data)
        }
    }

    func send(_ text: String) {
        send(Data(text.utf8))
    }

    // MARK: - Private

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        DispatchQueue.main.async { self.onStateChange?(newState) }
    }

    private func log(_ message: String) {
        print("JITerm link[\(name):\(port)]: \(message)")
    }

    private func run() {
        var failures = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !isStopped {
            setState(.connecting)
            let s = Self.connectLoopback(port: port)
            guard s >= 0 else {
                failures += 1
                if failures == 1 || failures % 50 == 0 {
                    log("ожидание QEMU (попытка \(failures), errno \(errno): \(String(cString: strerror(errno))))")
                }
                usleep(300_000)
                continue
            }
            log("подключено после \(failures) неудачных попыток")
            failures = 0

            lock.lock()
            fd = s
            let queued = pending
            pending.removeAll()
            lock.unlock()
            if !queued.isEmpty {
                writeQueue.async { Self.writeAll(s, queued) }
            }
            setState(.connected)

            var total = 0
            while true {
                let n = buffer.withUnsafeMutableBytes { read(s, $0.baseAddress, $0.count) }
                if n > 0 {
                    if total == 0 {
                        log("получены первые данные (\(n) байт)")
                    }
                    total += n
                    let chunk = Data(buffer[0..<n])
                    DispatchQueue.main.async { self.onData?(chunk) }
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }

            lock.lock()
            fd = -1
            lock.unlock()
            close(s)
            log("соединение закрыто (получено \(total) байт)")
            if !isStopped {
                setState(.connecting)
                usleep(300_000)
            }
        }
        setState(.closed)
    }

    static func connectLoopback(port: UInt16) -> Int32 {
        let s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard s >= 0 else { return -1 }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            let saved = errno
            close(s)
            errno = saved
            return -1
        }
        return s
    }

    static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard var ptr = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let n = Darwin.send(fd, ptr, remaining, 0)
                if n > 0 {
                    remaining -= n
                    ptr = ptr.advanced(by: n)
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}

enum PortAllocator {
    /// Возвращает свободный TCP-порт на 127.0.0.1 (bind к порту 0).
    static func freePort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard named == 0 else { return nil }
        return UInt16(bigEndian: addr.sin_port)
    }

    /// Можно ли занять порт (для проброса портов в гостя).
    static func isFree(_ port: UInt16, anyAddress: Bool) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = anyAddress ? 0 : inet_addr("127.0.0.1")
        addr.sin_port = port.bigEndian
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Несколько разных свободных портов.
    static func freePorts(_ count: Int) -> [UInt16] {
        var result: [UInt16] = []
        var attempts = 0
        while result.count < count && attempts < count * 10 {
            attempts += 1
            if let p = freePort(), !result.contains(p) {
                result.append(p)
            }
        }
        return result
    }
}
