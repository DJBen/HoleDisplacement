// Copyright © 2025 Snap, Inc. All rights reserved.

import UIKit
import MetalKit
import SwiftUI
import Combine

// Our iOS specific view controller
class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    
    private let settingsStore = DotFieldSettingsStore()
    private var cancellables: Set<AnyCancellable> = []
    private var activeTouchIDs: Set<Int> = []
    private lazy var impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    private lazy var settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        button.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        
        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor.black
        mtkView.isMultipleTouchEnabled = true
        mtkView.isUserInteractionEnabled = true

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        self.mtkView = mtkView
        
        settingsStore.settings.reduceMotion = UIAccessibility.isReduceMotionEnabled
        renderer.apply(settings: settingsStore.settings)
        observeSettings()
        registerReduceMotionObserver()
        installSettingsButton()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func touchIdentifier(for touch: UITouch) -> Int {
        return ObjectIdentifier(touch).hashValue
    }
    
    private func sendTouches(_ touches: Set<UITouch>, action: (Int, CGPoint) -> Void) {
        guard let targetView = mtkView else { return }
        for touch in touches {
            let location = touch.location(in: targetView)
            action(touchIdentifier(for: touch), location)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard renderer != nil else { return }
        
        let shouldPulse = settingsStore.settings.hapticsEnabled && activeTouchIDs.isEmpty && !touches.isEmpty
        if shouldPulse {
            impactGenerator.prepare()
            impactGenerator.impactOccurred(intensity: 0.6)
        }
        
        sendTouches(touches) { [weak self] identifier, location in
            self?.renderer.updateTouch(id: identifier, location: location)
            self?.activeTouchIDs.insert(identifier)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard renderer != nil else { return }
        sendTouches(touches) { [weak self] identifier, location in
            self?.renderer.updateTouch(id: identifier, location: location)
            self?.activeTouchIDs.insert(identifier)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard renderer != nil else { return }
        for touch in touches {
            renderer.endTouch(id: touchIdentifier(for: touch))
            activeTouchIDs.remove(touchIdentifier(for: touch))
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard renderer != nil else { return }
        for touch in touches {
            renderer.endTouch(id: touchIdentifier(for: touch))
            activeTouchIDs.remove(touchIdentifier(for: touch))
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        renderer?.resetTouches()
        activeTouchIDs.removeAll()
    }
    
    private func observeSettings() {
        settingsStore.$settings
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.renderer.apply(settings: newSettings)
            }
            .store(in: &cancellables)
    }
    
    private func registerReduceMotionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReduceMotionChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }
    
    private func installSettingsButton() {
        guard let targetView = mtkView else { return }
        targetView.addSubview(settingsButton)
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: targetView.safeAreaLayoutGuide.topAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: targetView.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            settingsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            settingsButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
    
    @objc private func handleReduceMotionChange() {
        let isEnabled = UIAccessibility.isReduceMotionEnabled
        renderer.systemReduceMotionChanged(isEnabled)
    }
    
    @objc private func showSettings() {
        let settingsView = DotFieldSettingsView(store: settingsStore,
                                                systemReduceMotionEnabled: UIAccessibility.isReduceMotionEnabled)
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.preferredCornerRadius = 24
        }
        present(hostingController, animated: true)
    }
}
