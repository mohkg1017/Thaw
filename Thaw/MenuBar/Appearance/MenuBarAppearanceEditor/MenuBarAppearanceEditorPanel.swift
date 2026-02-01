//
//  MenuBarAppearanceEditorPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

/// A popover that contains a portable version of the menu bar
/// appearance editor interface.
@MainActor
final class MenuBarAppearanceEditorPanel: NSObject, NSPopoverDelegate {
    /// The default screen to show the popover on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The underlying popover.
    private let popover = NSPopover()

    /// An invisible window used to anchor the popover to the top of the screen.
    private var anchorWindow: NSWindow?

    /// Sets up the popover.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configurePopover()
        configureContent(with: appState)
        configureObservers(with: appState)
    }

    /// Shows the popover on the given screen.
    func show(on screen: NSScreen) {
        guard let anchorView = anchorView(for: screen) else {
            return
        }
        updateContentSize()
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
    }

    // MARK: NSPopoverDelegate

    func popoverWillShow(_: Notification) {
        NSColorPanel.shared.hidesOnDeactivate = false
    }

    func popoverDidClose(_: Notification) {
        anchorWindow?.orderOut(nil)
        NSColorPanel.shared.hidesOnDeactivate = true
        NSColorPanel.shared.close()
    }

    // MARK: Private

    private func configurePopover() {
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
    }

    private func configureContent(with appState: AppState) {
        let controller = MenuBarAppearanceEditorHostingController(appState: appState)
        popover.contentViewController = controller
        popover.appearance = NSApp.effectiveAppearance
    }

    private func configureObservers(with appState: AppState) {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak popover] appearance in
                popover?.appearance = appearance
            }
            .store(in: &c)

        appState.appearanceManager.$configuration
            .sink { [weak self] _ in
                self?.updateContentSize()
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateContentSize() {
        guard
            let hostingController = popover.contentViewController as? MenuBarAppearanceEditorHostingController
        else {
            return
        }
        hostingController.updatePreferredContentSize()
        popover.contentSize = hostingController.preferredContentSize
    }

    private func anchorView(for screen: NSScreen) -> NSView? {
        let window: NSWindow
        if let anchorWindow {
            window = anchorWindow
        } else {
            let newWindow = NSWindow(
                contentRect: .init(origin: .zero, size: .init(width: 1, height: 1)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = .statusBar
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.contentView = NSView(
                frame: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
            anchorWindow = newWindow
            window = newWindow
        }

        let frame = screen.visibleFrame
        let origin = CGPoint(x: frame.midX, y: frame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()

        return window.contentView
    }
}

// MARK: - MenuBarAppearanceEditorHostingController

@MainActor
private final class MenuBarAppearanceEditorHostingController: NSHostingController<MenuBarAppearanceEditorContentView> {
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init(rootView: MenuBarAppearanceEditorContentView(appState: appState))
        updatePreferredContentSize()

        appState.appearanceManager.$configuration
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.updatePreferredContentSize()
                }
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreferredContentSize() {
        guard let appState else {
            preferredContentSize = NSSize(width: 500, height: 630)
            return
        }
        let isDynamic = appState.appearanceManager.configuration.isDynamic
        preferredContentSize = NSSize(width: 500, height: isDynamic ? 630 : 420)
        view.setFrameSize(preferredContentSize)
    }
}

// MARK: - MenuBarAppearanceEditorContentView

private struct MenuBarAppearanceEditorContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        MenuBarAppearanceEditor(
            appearanceManager: appState.appearanceManager,
            location: .panel
        )
        .environmentObject(appState)
    }
}
