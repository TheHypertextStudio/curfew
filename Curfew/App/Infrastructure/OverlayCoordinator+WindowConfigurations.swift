import AppKit

/// Window configurations for each overlay kind, kept beside
/// ``OverlayCoordinator`` so the coordinator body stays focused on window
/// lifecycle.
extension OverlayCoordinator {
    /// Window configuration for the translucent dim overlay shown during the
    /// warning phase. Mouse events pass through so normal interaction continues.
    static let warningWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: true,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    /// Window configuration for the full-screen lockout overlay. Level
    /// `.screenSaver` keeps it above the Dock and any full-screen app.
    /// Mouse events are captured so the user cannot interact with the desktop.
    static let lockoutWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    /// Window configuration for the small floating countdown timer shown at
    /// T-5 and below. Level `.screenSaver` keeps it above full-screen work.
    /// Mouse events pass through.
    static let timerWindowWidth: CGFloat = 240

    static let timerWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: true,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )

    /// Window configuration for the full-screen morning (sunrise) reflection
    /// overlay. Same commanding `.screenSaver` presence as the lockout so it
    /// owns the screen the moment it appears, but it is *not* paired with the
    /// key interceptor — the user can dismiss it (Start / Skip) at any time.
    static let daybreakWindowConfiguration = OverlayWindowConfiguration(
        styleMask: [.borderless],
        level: .screenSaver,
        ignoresMouseEvents: false,
        collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
        isMovable: false,
        hidesOnDeactivate: false
    )
}
