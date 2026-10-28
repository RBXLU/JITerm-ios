//
//  VNCClient.swift
//  JITerm
//
//  Минимальный клиент RFB 3.8 (VNC) для рабочего стола внутри Linux.
//  Сервер — Xvnc (TigerVNC) в госте, порт 5901 проброшен на 127.0.0.1 iPhone.
//  Поддерживаются кодировки Raw и CopyRect и псевдокодировка DesktopSize;
//  по локальному соединению этого достаточно.
//

import CoreGraphics
import Foundation

final class VNCClient {
    enum State: Equatable {
        case idle
        case connecting
        case connected(width: Int, height: Int, name: String)
        case failed(String)
    }

    /// Все колбэки вызываются на главной очереди.
    var onStateChange: ((State) -> Void)?
    var onFrame: ((CGImage) -> Void)?
    var onBell: (() -> Void)?
    var onClipboard: ((String) -> Void)?

    private let port: UInt16
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "jiterm.vnc.write", qos: .userInteractive)
    private var fd: Int32 = -1
    private var stopped = true
    private var thread: Thread?

    private var width = 0
    private var height = 0
    private var framebuffer = [UInt8]()
    private var renderScheduled = false
    private var buttons: UInt8 = 0

    init(port: UInt16) {
        self.port = port
    }

    // MARK: - Публичный API

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard thread == nil else { return }
        stopped = false
        let t = Thread { [weak self] in self?.run() }
        t.name = "jiterm.vnc"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        lock.lock()
        stopped = true
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        lock.unlock()
    }

    /// Абсолютное положение мыши в пикселях рабочего стола + кнопки
    /// (бит 0 — левая, 1 — средняя, 2 — правая, 3/4 — колесо вверх/вниз).
    func pointer(x: Int, y: Int, buttons: UInt8) {
        self.buttons = buttons
        let px = UInt16(clamping: max(0, x)), py = UInt16(clamping: max(0, y))
        send([5, buttons, UInt8(px >> 8), UInt8(px & 0xff), UInt8(py >> 8), UInt8(py & 0xff)])
    }

    func click(x: Int, y: Int, button: UInt8 = 1) {
        pointer(x: x, y: y, buttons: 0)
        pointer(x: x, y: y, buttons: button)
        pointer(x: x, y: y, buttons: 0)
    }

    func scroll(x: Int, y: Int, up: Bool, steps: Int = 1) {
        let bit: UInt8 = up ? 8 : 16
        for _ in 0..<max(1, steps) {
            pointer(x: x, y: y, buttons: bit)
            pointer(x: x, y: y, buttons: 0)
        }
    }

    func key(_ keysym: UInt32, down: Bool) {
        send([4, down ? 1 : 0, 0, 0,
              UInt8((keysym >> 24) & 0xff), UInt8((keysym >> 16) & 0xff),
              UInt8((keysym >> 8) & 0xff), UInt8(keysym & 0xff)])
    }

    func tap(_ keysym: UInt32, modifiers: [UInt32] = []) {
        modifiers.forEach { key($0, down: true) }
        key(keysym, down: true)
        key(keysym, down: false)
        modifiers.reversed().forEach { key($0, down: false) }
    }

    /// Ввод текста (с экранной клавиатуры).
    func type(_ text: String, modifiers: [UInt32] = []) {
        for scalar in text.unicodeScalars {
            tap(Keysym.forScalar(scalar), modifiers: modifiers)
        }
    }

    // MARK: - Сеть

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func setState(_ state: State) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    private func send(_ bytes: [UInt8]) {
        let data = Data(bytes)
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let fd = self.fd
            self.lock.unlock()
            if fd >= 0 { LoopbackLink.writeAll(fd, data) }
        }
    }

    private enum RFBError: Error {
        case closed
        case protocolError(String)
    }

    private func run() {
        var announcedWaiting = false
        while !isStopped {
            if !announcedWaiting { setState(.connecting) }
            let s = LoopbackLink.connectLoopback(port: port)
            if s < 0 {
                announcedWaiting = true
                sleep(2)
                continue
            }
            lock.lock()
            fd = s
            lock.unlock()
            do {
                try session(s)
            } catch RFBError.protocolError(let message) {
                setState(.failed(message))
                announcedWaiting = true
            } catch {
                // Рабочий стол не запущен (slirp закрывает соединение) — ждём
                if !announcedWaiting { setState(.connecting) }
                announcedWaiting = true
            }
            lock.lock()
            fd = -1
            lock.unlock()
            close(s)
            if !isStopped { sleep(2) }
        }
        setState(.idle)
        lock.lock()
        thread = nil
        lock.unlock()
    }

    private func readExact(_ s: Int32, _ count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        try buffer.withUnsafeMutableBytes { raw in
            try readInto(s, raw.baseAddress!, count)
        }
        return buffer
    }

    private func readInto(_ s: Int32, _ pointer: UnsafeMutableRawPointer, _ count: Int) throws {
        var offset = 0
        while offset < count {
            let n = read(s, pointer.advanced(by: offset), count - offset)
            if n > 0 {
                offset += n
            } else if n < 0 && errno == EINTR {
                continue
            } else {
                throw RFBError.closed
            }
        }
    }

    private func u16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    private func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }

    private func session(_ s: Int32) throws {
        // Версия протокола
        let version = String(decoding: try readExact(s, 12), as: UTF8.self)
        guard version.hasPrefix("RFB ") else { throw RFBError.closed }
        let minor = Int(version.dropFirst(8).prefix(3)) ?? 3
        let useMinor = minor >= 8 ? 8 : (minor == 7 ? 7 : 3)
        LoopbackLink.writeAll(s, Data(String(format: "RFB 003.%03d\n", useMinor).utf8))

        // Безопасность: только «без пароля» (порт доступен лишь на этом iPhone)
        if useMinor >= 7 {
            let count = Int(try readExact(s, 1)[0])
            if count == 0 {
                let len = Int(u32(try readExact(s, 4), 0))
                let reason = String(decoding: try readExact(s, len), as: UTF8.self)
                throw RFBError.protocolError("VNC-сервер отказал: \(reason)")
            }
            let types = try readExact(s, count)
            guard types.contains(1) else {
                throw RFBError.protocolError("VNC-сервер требует пароль. Запустите рабочий стол командой jiterm-desktop.")
            }
            LoopbackLink.writeAll(s, Data([1]))
            if useMinor >= 8 {
                let result = u32(try readExact(s, 4), 0)
                if result != 0 { throw RFBError.protocolError("VNC: ошибка авторизации") }
            }
        } else {
            let type = u32(try readExact(s, 4), 0)
            guard type == 1 else { throw RFBError.protocolError("VNC-сервер требует пароль") }
        }

        // ClientInit (shared) → ServerInit
        LoopbackLink.writeAll(s, Data([1]))
        let header = try readExact(s, 24)
        let w = u16(header, 0), h = u16(header, 2)
        let nameLength = Int(u32(header, 20))
        let name = String(decoding: try readExact(s, nameLength), as: UTF8.self)

        // Формат пикселей: 32 бита, little-endian, 0x00RRGGBB → в памяти B,G,R,X
        let pixelFormat: [UInt8] = [0, 0, 0, 0, 32, 24, 0, 1, 0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0]
        LoopbackLink.writeAll(s, Data(pixelFormat))
        // Кодировки: CopyRect, Raw, DesktopSize (-223)
        var encodings: [UInt8] = [2, 0, 0, 3]
        for e in [Int32(1), 0, -223] {
            let v = UInt32(bitPattern: e)
            encodings += [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        }
        LoopbackLink.writeAll(s, Data(encodings))

        resize(width: w, height: h)
        setState(.connected(width: w, height: h, name: name))
        requestUpdate(s, incremental: false)

        while !isStopped {
            let type = try readExact(s, 1)[0]
            switch type {
            case 0:
                try readFramebufferUpdate(s)
                scheduleRender()
                requestUpdate(s, incremental: true)
            case 1: // SetColourMapEntries — не используется в true color
                let b = try readExact(s, 5)
                _ = try readExact(s, u16(b, 3) * 6)
            case 2:
                DispatchQueue.main.async { self.onBell?() }
            case 3:
                let b = try readExact(s, 7)
                let len = Int(u32(b, 3))
                let text = String(decoding: try readExact(s, len), as: UTF8.self)
                DispatchQueue.main.async { self.onClipboard?(text) }
            default:
                throw RFBError.protocolError("VNC: неизвестное сообщение \(type)")
            }
        }
    }

    private func requestUpdate(_ s: Int32, incremental: Bool) {
        lock.lock()
        let w = width, h = height
        lock.unlock()
        LoopbackLink.writeAll(s, Data([3, incremental ? 1 : 0, 0, 0, 0, 0,
                                       UInt8(w >> 8), UInt8(w & 0xff), UInt8(h >> 8), UInt8(h & 0xff)]))
    }

    private func resize(width w: Int, height h: Int) {
        lock.lock()
        width = w
        height = h
        framebuffer = [UInt8](repeating: 0, count: w * h * 4)
        lock.unlock()
    }

    private func readFramebufferUpdate(_ s: Int32) throws {
        let b = try readExact(s, 3)
        let count = u16(b, 1)
        for _ in 0..<count {
            let r = try readExact(s, 12)
            let x = u16(r, 0), y = u16(r, 2), w = u16(r, 4), h = u16(r, 6)
            let encoding = Int32(bitPattern: u32(r, 8))
            switch encoding {
            case 0: // Raw
                try readRaw(s, x: x, y: y, w: w, h: h)
            case 1: // CopyRect
                let src = try readExact(s, 4)
                copyRect(fromX: u16(src, 0), fromY: u16(src, 2), x: x, y: y, w: w, h: h)
            case -223: // DesktopSize
                resize(width: w, height: h)
                DispatchQueue.main.async { self.onStateChange?(.connected(width: w, height: h, name: "")) }
            default:
                throw RFBError.protocolError("VNC: неподдерживаемая кодировка \(encoding)")
            }
        }
    }

    private func readRaw(_ s: Int32, x: Int, y: Int, w: Int, h: Int) throws {
        let rowBytes = w * 4
        lock.lock()
        let fbWidth = width, fbHeight = height
        lock.unlock()
        guard x + w <= fbWidth, y + h <= fbHeight else {
            // Прямоугольник за пределами буфера — дочитываем и пропускаем
            _ = try readExact(s, rowBytes * h)
            return
        }
        var row = [UInt8](repeating: 0, count: rowBytes)
        for line in 0..<h {
            try row.withUnsafeMutableBytes { try readInto(s, $0.baseAddress!, rowBytes) }
            lock.lock()
            let offset = ((y + line) * width + x) * 4
            if offset + rowBytes <= framebuffer.count {
                framebuffer.withUnsafeMutableBytes { dst in
                    row.withUnsafeBytes { src in
                        (dst.baseAddress! + offset).copyMemory(from: src.baseAddress!, byteCount: rowBytes)
                    }
                }
            }
            lock.unlock()
        }
    }

    private func copyRect(fromX sx: Int, fromY sy: Int, x: Int, y: Int, w: Int, h: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard sx + w <= width, sy + h <= height, x + w <= width, y + h <= height else { return }
        let rowBytes = w * 4
        var temp = [UInt8](repeating: 0, count: rowBytes * h)
        for line in 0..<h {
            let src = ((sy + line) * width + sx) * 4
            temp.replaceSubrange(line * rowBytes..<(line + 1) * rowBytes, with: framebuffer[src..<src + rowBytes])
        }
        for line in 0..<h {
            let dst = ((y + line) * width + x) * 4
            framebuffer.replaceSubrange(dst..<dst + rowBytes, with: temp[line * rowBytes..<(line + 1) * rowBytes])
        }
    }

    /// Не чаще ~30 кадров в секунду собираем CGImage и отдаём на экран.
    private func scheduleRender() {
        lock.lock()
        if renderScheduled {
            lock.unlock()
            return
        }
        renderScheduled = true
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.renderScheduled = false
            let w = self.width, h = self.height
            let data = Data(self.framebuffer)
            self.lock.unlock()
            guard w > 0, h > 0, let provider = CGDataProvider(data: data as CFData) else { return }
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: info, provider: provider, decode: nil,
                                   shouldInterpolate: true, intent: .defaultIntent) {
                self.onFrame?(image)
            }
        }
    }
}

/// X11 keysym'ы для специальных клавиш.
enum Keysym {
    static let backspace: UInt32 = 0xff08
    static let tab: UInt32 = 0xff09
    static let enter: UInt32 = 0xff0d
    static let escape: UInt32 = 0xff1b
    static let home: UInt32 = 0xff50
    static let left: UInt32 = 0xff51
    static let up: UInt32 = 0xff52
    static let right: UInt32 = 0xff53
    static let down: UInt32 = 0xff54
    static let pageUp: UInt32 = 0xff55
    static let pageDown: UInt32 = 0xff56
    static let end: UInt32 = 0xff57
    static let delete: UInt32 = 0xffff
    static let shift: UInt32 = 0xffe1
    static let control: UInt32 = 0xffe3
    static let alt: UInt32 = 0xffe9
    static let superKey: UInt32 = 0xffeb
    static func function(_ n: Int) -> UInt32 { 0xffbe + UInt32(max(1, min(12, n)) - 1) }

    static func forScalar(_ scalar: Unicode.Scalar) -> UInt32 {
        switch scalar {
        case "\n", "\r": return enter
        case "\t": return tab
        default:
            let v = scalar.value
            // Latin-1 совпадает с keysym; остальное — Unicode keysym 0x01000000+код
            return v < 0x100 ? v : 0x0100_0000 | v
        }
    }
}
