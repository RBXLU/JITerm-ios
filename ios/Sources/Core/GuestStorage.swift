//
//  GuestStorage.swift
//  JITerm
//
//  Файлы гостевой системы: ядро и initramfs читаются прямо из бандла,
//  диск (qcow2) при первом запуске копируется в Application Support,
//  общая папка — Documents (видна в приложении «Файлы»).
//

import Foundation

struct GuestInfo: Decodable {
    var alpine: String
    var kernel: String
    var python: String
    var diskSize: String
    var built: String
}

enum GuestStorageError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "В приложении нет файла \(name). Сборка IPA неполная — пересоберите её через GitHub Actions."
        }
    }
}

enum GuestStorage {
    static var bundleGuestURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Guest", isDirectory: true)
    }

    static var bundledKernelURL: URL { bundleGuestURL.appendingPathComponent("vmlinuz-virt") }
    static var bundledInitrdURL: URL { bundleGuestURL.appendingPathComponent("initramfs-virt") }
    static var bundledDiskURL: URL { bundleGuestURL.appendingPathComponent("rootfs.qcow2") }

    static var qemuLibraryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Frameworks/qemu-aarch64-softmmu.framework/qemu-aarch64-softmmu")
    }

    static var dataURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("JITerm", isDirectory: true)
    }

    static var diskURL: URL { dataURL.appendingPathComponent("rootfs.qcow2") }
    /// Ядро и initramfs хранятся рядом с диском: модули ядра лежат на диске,
    /// поэтому при обновлении приложения ядро не должно меняться.
    static var kernelURL: URL { dataURL.appendingPathComponent("vmlinuz-virt") }
    static var initrdURL: URL { dataURL.appendingPathComponent("initramfs-virt") }

    static var sharedURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var logURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qemu.log")
    }

    static var info: GuestInfo? {
        guard let data = try? Data(contentsOf: bundleGuestURL.appendingPathComponent("guest.json")) else { return nil }
        return try? JSONDecoder().decode(GuestInfo.self, from: data)
    }

    /// Сброс диска, запрошенный во время работы ВМ, выполняется при следующем запуске.
    static let resetPendingKey = "storage.resetPending"

    static var diskExists: Bool {
        FileManager.default.fileExists(atPath: diskURL.path)
    }

    /// Размер файла диска на iPhone (сколько реально занято).
    static var diskUsageBytes: Int64 {
        let values = try? diskURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    /// Проверяет ресурсы и при необходимости разворачивает диск.
    static func prepare() throws {
        let fm = FileManager.default
        for url in [bundledKernelURL, bundledInitrdURL, bundledDiskURL, qemuLibraryURL] where !fm.fileExists(atPath: url.path) {
            throw GuestStorageError.missingResource(url.lastPathComponent)
        }
        try fm.createDirectory(at: dataURL, withIntermediateDirectories: true)
        var dataDir = dataURL
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? dataDir.setResourceValues(rv)

        if UserDefaults.standard.bool(forKey: resetPendingKey) {
            try resetDisk()
            UserDefaults.standard.set(false, forKey: resetPendingKey)
        }
        if !fm.fileExists(atPath: diskURL.path) {
            let tmp = dataURL.appendingPathComponent("rootfs.qcow2.part")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: bundledDiskURL, to: tmp)
            try? fm.removeItem(at: kernelURL)
            try? fm.removeItem(at: initrdURL)
            try fm.moveItem(at: tmp, to: diskURL)
        }
        // Новый диск (или диск от версии, где ядро бралось из приложения) — берём ядро из приложения
        for (bundled, installed) in [(bundledKernelURL, kernelURL), (bundledInitrdURL, initrdURL)]
        where !fm.fileExists(atPath: installed.path) {
            try fm.copyItem(at: bundled, to: installed)
        }
        try fm.createDirectory(at: sharedURL, withIntermediateDirectories: true)
        let readme = sharedURL.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            let text = """
            Эта папка доступна внутри Linux как /root/shared (~/shared).
            Кладите сюда файлы через приложение «Файлы» → «На iPhone» → JITerm.

            This folder is mounted inside Linux at /root/shared.
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    /// Удаляет диск — при следующем запуске система развернётся заново.
    static func resetDisk() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: diskURL.path) {
            try fm.removeItem(at: diskURL)
        }
        try? fm.removeItem(at: kernelURL)
        try? fm.removeItem(at: initrdURL)
    }
}
