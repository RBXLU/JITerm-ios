//
//  BackgroundKeeper.swift
//  JITerm
//
//  Держит приложение (и Linux внутри) активным в фоне через обновления
//  геолокации — как навигатор. Координаты никуда не сохраняются и не
//  передаются: обновления просто игнорируются. Точность минимальная
//  (~3 км), чтобы экономить батарею.
//

import CoreLocation
import Foundation

final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundKeeper()

    private let manager = CLLocationManager()
    private(set) var isRunning = false
    private var wantsToRun = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    var isEnabledInSettings: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.backgroundMode)
    }

    var authorizationDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Включает или выключает фоновый режим в зависимости от настроек и состояния ВМ.
    func update(vmActive: Bool) {
        wantsToRun = vmActive && isEnabledInSettings
        wantsToRun ? start() : stop()
    }

    private func start() {
        guard !isRunning else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            // Продолжим в locationManagerDidChangeAuthorization
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            print("JITerm: фоновый режим недоступен — доступ к геолокации запрещён в Настройках iOS")
            return
        default:
            break
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isRunning = true
        print("JITerm: фоновый режим включён (геолокация)")
    }

    private func stop() {
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
        print("JITerm: фоновый режим выключен")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if wantsToRun {
            start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Координаты не нужны — важен только сам факт активной геолокации.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("JITerm: геолокация: \(error.localizedDescription)")
    }
}
