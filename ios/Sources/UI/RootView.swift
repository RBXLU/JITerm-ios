//
//  RootView.swift
//  JITerm
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var vm: VirtualMachine
    @EnvironmentObject private var appearance: AppearanceController
    @AppStorage(SettingsKey.autostart) private var autostart = true

    var body: some View {
        ZStack {
            Color(appearance.theme.background).ignoresSafeArea()
            switch vm.state {
            case .waitingForJIT:
                JITWaitView()
            case .idle:
                StartView()
            default:
                TerminalScreen()
            }
        }
        .onAppear {
            if let demo = DemoMode.current {
                vm.enterDemo(demo)
            } else if autostart {
                vm.start()
            } else if !vm.jitEnabled {
                vm.start() // покажет экран ожидания JIT
            }
        }
    }
}

/// Показывается, если автозапуск выключен.
struct StartView: View {
    @EnvironmentObject private var vm: VirtualMachine
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.green)
            Text("JITerm")
                .font(.largeTitle.bold())
            Text("Alpine Linux · aarch64 · QEMU JIT")
                .foregroundStyle(.secondary)
            Button {
                vm.start()
            } label: {
                Label("Запустить Linux", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Button("Настройки") { showSettings = true }
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}
