//
//  DesktopView.swift
//  JITerm
//
//  Показ рабочего стола Linux (кадры от VNCClient) и управление:
//  • касание — клик левой кнопкой, долгое нажатие — правой;
//  • ведение одним пальцем — перетаскивание (зажатая левая кнопка);
//  • два пальца — прокрутка/масштаб картинки (щипок);
//  • экранная и аппаратная клавиатура → X11 keysym'ы.
//

import SwiftUI
import UIKit

final class DesktopModel: ObservableObject {
    static let shared = DesktopModel()

    @Published private(set) var state: VNCClient.State = .idle
    @Published var ctrl = false
    @Published var alt = false
    @Published var superKey = false
    @Published var shift = false

    private(set) var client: VNCClient?
    private var port: UInt16?
    private var lastImage: CGImage?
    weak var view: DesktopView?

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// Подключение к VNC рабочего стола (переподключается само, пока запущен Linux).
    func connect(port: UInt16?) {
        guard let port else { return }
        if self.port == port, client != nil { return }
        client?.stop()
        self.port = port
        let client = VNCClient(port: port)
        client.onStateChange = { [weak self] state in
            self?.state = state
        }
        client.onFrame = { [weak self] image in
            self?.lastImage = image
            self?.view?.show(image)
        }
        client.onClipboard = { text in
            UIPasteboard.general.string = text
        }
        client.onBell = {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        self.client = client
        client.start()
    }

    func disconnect() {
        client?.stop()
        client = nil
        port = nil
        state = .idle
    }

    func attach(_ view: DesktopView) {
        self.view = view
        view.model = self
        if let image = lastImage {
            view.show(image)
        }
    }

    /// Модификаторы, нажатые на панели (срабатывают на одно нажатие).
    func takeModifiers() -> [UInt32] {
        var mods: [UInt32] = []
        if ctrl { mods.append(Keysym.control) }
        if alt { mods.append(Keysym.alt) }
        if superKey { mods.append(Keysym.superKey) }
        if shift { mods.append(Keysym.shift) }
        if !mods.isEmpty {
            ctrl = false; alt = false; superKey = false; shift = false
        }
        return mods
    }

    func tap(_ keysym: UInt32) {
        client?.tap(keysym, modifiers: takeModifiers())
    }

    func type(_ text: String) {
        client?.type(text, modifiers: takeModifiers())
    }

    func scroll(up: Bool) {
        view?.scrollWheel(up: up)
    }
}

final class DesktopView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var model: DesktopModel?

    private let scrollView = UIScrollView()
    private let canvas = UIView()
    private let keyInput = DesktopKeyInput()
    private var framebufferSize = CGSize.zero
    private var lastPointer = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        scrollView.delegate = self
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        addSubview(scrollView)

        canvas.layer.minificationFilter = .trilinear
        canvas.layer.magnificationFilter = .linear
        canvas.backgroundColor = .black
        scrollView.addSubview(canvas)

        keyInput.desktop = self
        keyInput.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        keyInput.alpha = 0.01
        addSubview(keyInput)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        let drag = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        drag.minimumNumberOfTouches = 1
        drag.maximumNumberOfTouches = 1
        tap.require(toFail: longPress)
        for g in [tap, longPress, drag] as [UIGestureRecognizer] {
            g.delegate = self
            canvas.addGestureRecognizer(g)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Кадры

    func show(_ image: CGImage) {
        canvas.layer.contents = image
        let size = CGSize(width: image.width, height: image.height)
        if size != framebufferSize {
            framebufferSize = size
            scrollView.zoomScale = 1
            canvas.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            updateZoom(reset: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let atMinimum = scrollView.zoomScale <= scrollView.minimumZoomScale + 0.001
        scrollView.frame = bounds
        updateZoom(reset: atMinimum)
    }

    private func updateZoom(reset: Bool) {
        guard framebufferSize.width > 0, bounds.width > 0 else { return }
        let fit = min(bounds.width / framebufferSize.width, bounds.height / framebufferSize.height)
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 6, 3)
        if reset || scrollView.zoomScale < fit {
            scrollView.zoomScale = fit
        }
        centerContent()
    }

    private func centerContent() {
        let content = scrollView.contentSize
        let dx = max(0, (bounds.width - content.width) / 2)
        let dy = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    // MARK: - Мышь

    private func framebufferPoint(_ gesture: UIGestureRecognizer) -> (Int, Int) {
        let p = gesture.location(in: canvas)
        lastPointer = p
        let x = Int(min(max(0, p.x), max(0, framebufferSize.width - 1)))
        let y = Int(min(max(0, p.y), max(0, framebufferSize.height - 1)))
        return (x, y)
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let client = model?.client else { return }
        let (x, y) = framebufferPoint(g)
        let mods = model?.takeModifiers() ?? []
        mods.forEach { client.key($0, down: true) }
        client.click(x: x, y: y, button: 1)
        mods.reversed().forEach { client.key($0, down: false) }
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let client = model?.client else { return }
        let (x, y) = framebufferPoint(g)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        client.click(x: x, y: y, button: 4) // правая кнопка
    }

    @objc private func handleDrag(_ g: UIPanGestureRecognizer) {
        guard let client = model?.client else { return }
        let (x, y) = framebufferPoint(g)
        switch g.state {
        case .began, .changed:
            client.pointer(x: x, y: y, buttons: 1)
        default:
            client.pointer(x: x, y: y, buttons: 0)
        }
    }

    func scrollWheel(up: Bool) {
        guard let client = model?.client else { return }
        client.scroll(x: Int(lastPointer.x), y: Int(lastPointer.y), up: up, steps: 3)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }

    // MARK: - Клавиатура

    var isKeyboardVisible: Bool { keyInput.isFirstResponder }

    func toggleKeyboard() {
        if keyInput.isFirstResponder {
            _ = keyInput.resignFirstResponder()
        } else {
            _ = keyInput.becomeFirstResponder()
        }
    }

    func hideKeyboard() {
        _ = keyInput.resignFirstResponder()
    }

    fileprivate func insert(_ text: String) {
        model?.type(text)
    }

    fileprivate func backspace() {
        model?.tap(Keysym.backspace)
    }

    fileprivate func hardwareKey(_ keysym: UInt32, down: Bool) {
        model?.client?.key(keysym, down: down)
    }
}

/// Невидимый приёмник ввода: экранная клавиатура iOS и аппаратная клавиатура.
final class DesktopKeyInput: UIView, UIKeyInput {
    weak var desktop: DesktopView?

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardAppearance: UIKeyboardAppearance = .dark

    func insertText(_ text: String) { desktop?.insert(text) }
    func deleteBackward() { desktop?.backspace() }

    // Аппаратная клавиатура: служебные клавиши и модификаторы передаём напрямую
    private static let hardwareMap: [UIKeyboardHIDUsage: UInt32] = [
        .keyboardEscape: Keysym.escape,
        .keyboardLeftArrow: Keysym.left, .keyboardRightArrow: Keysym.right,
        .keyboardUpArrow: Keysym.up, .keyboardDownArrow: Keysym.down,
        .keyboardHome: Keysym.home, .keyboardEnd: Keysym.end,
        .keyboardPageUp: Keysym.pageUp, .keyboardPageDown: Keysym.pageDown,
        .keyboardDeleteForward: Keysym.delete,
        .keyboardLeftControl: Keysym.control, .keyboardRightControl: Keysym.control,
        .keyboardLeftAlt: Keysym.alt, .keyboardRightAlt: Keysym.alt,
        .keyboardLeftGUI: Keysym.superKey, .keyboardRightGUI: Keysym.superKey,
        .keyboardF1: Keysym.function(1), .keyboardF2: Keysym.function(2), .keyboardF3: Keysym.function(3),
        .keyboardF4: Keysym.function(4), .keyboardF5: Keysym.function(5), .keyboardF6: Keysym.function(6),
        .keyboardF7: Keysym.function(7), .keyboardF8: Keysym.function(8), .keyboardF9: Keysym.function(9),
        .keyboardF10: Keysym.function(10), .keyboardF11: Keysym.function(11), .keyboardF12: Keysym.function(12),
    ]

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if let key = press.key, let keysym = Self.hardwareMap[key.keyCode] {
                desktop?.hardwareKey(keysym, down: true)
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            if let key = press.key, let keysym = Self.hardwareMap[key.keyCode] {
                desktop?.hardwareKey(keysym, down: false)
            } else {
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }
}

struct DesktopHostView: UIViewRepresentable {
    let model: DesktopModel

    func makeUIView(context: Context) -> DesktopView {
        let view = DesktopView()
        model.attach(view)
        return view
    }

    func updateUIView(_ view: DesktopView, context: Context) {
        if model.view !== view {
            model.attach(view)
        }
    }
}
