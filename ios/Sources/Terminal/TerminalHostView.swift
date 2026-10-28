//
//  TerminalHostView.swift
//  JITerm
//
//  Показывает TerminalView выбранной вкладки. Сами TerminalView живут
//  в TerminalSession, поэтому вывод не теряется при переключении вкладок.
//

import SwiftTerm
import SwiftUI
import UIKit

struct TerminalHostView: UIViewRepresentable {
    let session: TerminalSession
    let background: UIColor
    var focusToken: Int
    /// false — открыт лист/оверлей: клавиатура терминала не должна его перекрывать.
    var isActive: Bool = true

    func makeUIView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.show(session.terminalView)
        return view
    }

    func updateUIView(_ view: TerminalContainerView, context: Context) {
        view.backgroundColor = background
        view.show(session.terminalView)
        let terminal = session.terminalView
        if !isActive {
            if terminal.isFirstResponder {
                _ = terminal.resignFirstResponder()
            }
            // При возвращении в терминал клавиатура появится снова
            context.coordinator.lastFocusToken = -1
        } else if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                _ = terminal.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastFocusToken = -1
    }
}

final class TerminalContainerView: UIView {
    private weak var current: TerminalView?
    private var pinchStart: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ terminal: TerminalView) {
        guard current !== terminal else { return }
        let wasFirstResponder = current?.isFirstResponder ?? false
        current?.removeFromSuperview()
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            terminal.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            terminal.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            terminal.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])
        current = terminal
        if wasFirstResponder {
            _ = terminal.becomeFirstResponder()
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStart = CGFloat(UserDefaults.standard.double(forKey: SettingsKey.fontSize))
        case .changed:
            let size = min(32, max(7, (pinchStart * gesture.scale).rounded()))
            if size != CGFloat(UserDefaults.standard.double(forKey: SettingsKey.fontSize)) {
                UserDefaults.standard.set(Double(size), forKey: SettingsKey.fontSize)
            }
        default:
            break
        }
    }
}
