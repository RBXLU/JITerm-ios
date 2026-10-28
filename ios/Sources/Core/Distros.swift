//
//  Distros.swift
//  JITerm
//
//  Выбор системы для загрузки. Alpine встроен в приложение; Debian и
//  Arch Linux ARM ставятся из Alpine командой `jiterm-install` в
//  Documents/.jiterm/distros/<id>/ (disk.img + ядро + initrd + distro.json).
//

import Foundation

/// Описание установленной системы (distro.json, пишет jiterm-install).
struct DistroInfo: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var kernel: String
    var initrd: String
    var disk: String
    var diskFormat: String
    var cmdline: String
    var installed: String?
}

/// Системы, которые можно установить из Alpine.
struct InstallableDistro: Identifiable {
    let id: String
    let title: String
    let note: String

    static let all: [InstallableDistro] = [
        InstallableDistro(id: "debian", title: "Debian 13",
                          note: "apt, ≈1,5 ГБ, установка 20–60 мин"),
        InstallableDistro(id: "arch", title: "Arch Linux ARM",
                          note: "pacman, скачивание ≈800 МБ, ≈2,5 ГБ"),
    ]
}

/// Что именно загружать: ядро, initrd, диск и параметры ядра.
struct BootTarget {
    var id: String
    var title: String
    var kernel: URL
    var initrd: URL
    var disk: URL
    var diskFormat: String
    var baseCmdline: String
    var isBuiltIn: Bool

    static let builtInID = "alpine"

    static var builtIn: BootTarget {
        BootTarget(id: builtInID,
                   title: "Alpine Linux",
                   kernel: GuestStorage.kernelURL,
                   initrd: GuestStorage.initrdURL,
                   disk: GuestStorage.diskURL,
                   diskFormat: "qcow2",
                   baseCmdline: "root=/dev/vda rootfstype=ext4 modules=ext4 console=ttyAMA0",
                   isBuiltIn: true)
    }
}

enum DistroCatalog {
    static var rootURL: URL {
        GuestStorage.sharedURL.appendingPathComponent(".jiterm/distros", isDirectory: true)
    }

    /// Установленные системы (кроме встроенного Alpine).
    static func installed() -> [DistroInfo] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return dirs.compactMap { dir -> DistroInfo? in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("distro.json")),
                  let info = try? JSONDecoder().decode(DistroInfo.self, from: data) else { return nil }
            return info
        }
        .sorted { $0.title < $1.title }
    }

    static func directory(for id: String) -> URL {
        rootURL.appendingPathComponent(id, isDirectory: true)
    }

    /// Цель загрузки для выбранной системы; nil — файлы системы не найдены.
    static func bootTarget(for id: String) -> BootTarget? {
        if id == BootTarget.builtInID {
            return .builtIn
        }
        guard let info = installed().first(where: { $0.id == id }) else { return nil }
        let dir = directory(for: id)
        let target = BootTarget(id: info.id,
                                title: info.title,
                                kernel: dir.appendingPathComponent(info.kernel),
                                initrd: dir.appendingPathComponent(info.initrd),
                                disk: dir.appendingPathComponent(info.disk),
                                diskFormat: info.diskFormat,
                                baseCmdline: info.cmdline,
                                isBuiltIn: false)
        let fm = FileManager.default
        guard [target.kernel, target.initrd, target.disk].allSatisfy({ fm.fileExists(atPath: $0.path) }) else {
            return nil
        }
        return target
    }

    /// Занятое на iPhone место (диски разреженные — считаем реально выделенное).
    static func usageBytes(for id: String) -> Int64 {
        let dir = directory(for: id)
        guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in files {
            let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }

    static func remove(_ id: String) throws {
        guard id != BootTarget.builtInID else { return }
        try FileManager.default.removeItem(at: directory(for: id))
        if UserDefaults.standard.string(forKey: SettingsKey.bootDistro) == id {
            UserDefaults.standard.set(BootTarget.builtInID, forKey: SettingsKey.bootDistro)
        }
    }

    /// Диски систем не должны попадать в резервную копию iCloud.
    static func excludeFromBackup() {
        let jiterm = GuestStorage.sharedURL.appendingPathComponent(".jiterm", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var url = jiterm
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
