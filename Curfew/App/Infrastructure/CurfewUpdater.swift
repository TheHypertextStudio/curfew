import Combine
import Foundation
import SwiftUI

// Sparkle autoupdate integration.
//
// To activate:
//   1. In Xcode → project → Package Dependencies, add:
//      https://github.com/sparkle-project/Sparkle  from: 2.7.0
//   2. In Curfew target → Frameworks, Libraries, and Embedded Content, add
//      Sparkle.framework (Embed & Sign).
//   3. Add `SUFeedURL = https://curfew.hypertext.studio/appcast.xml` to Info.plist.
//   4. Generate an EdDSA key pair:
//        .build/artifacts/sparkle/.../generate_keys
//      Add the public key to Info.plist as SUPublicEDKey.
//      Store the private key in GitHub Secrets as SPARKLE_PRIVATE_KEY.
//   5. Add `-DSPARKLE_ENABLED` to the Curfew target's Other Swift Flags.
//
// Without those steps `CurfewUpdater` falls back to a no-op stub so the rest
// of the project compiles and the Check for Updates menu item remains visible
// but disabled.

#if canImport(Sparkle)

    import Sparkle

    /// Live updater backed by Sparkle.
    @MainActor
    final class CurfewUpdater: ObservableObject {
        private let controller: SPUStandardUpdaterController

        /// Whether the Sparkle updater is currently in a state where it
        /// can start an update check. Drives the menu-item enabled state.
        @Published private(set) var canCheckForUpdates = false

        /// Boots Sparkle's standard controller on the main actor. Sparkle
        /// begins polling the appcast as soon as it is created.
        init() {
            self.controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.canCheckForUpdates = controller.updater.canCheckForUpdates
        }

        /// Invoked from the Check for Updates… menu item. Triggers a
        /// user-initiated update check and refreshes the availability flag.
        func checkForUpdates() {
            controller.checkForUpdates(nil)
            canCheckForUpdates = controller.updater.canCheckForUpdates
        }
    }

#else

    /// No-op stub used when Sparkle.framework is not yet linked into the Xcode
    /// project. The Check for Updates menu item stays visible but disabled.
    @MainActor
    final class CurfewUpdater: ObservableObject {
        /// Always `false` in the stub — keeps the menu item disabled.
        @Published private(set) var canCheckForUpdates = false
        /// No-op init.
        nonisolated init() {}
        /// No-op; menu item is disabled so this never fires in practice.
        func checkForUpdates() {}
    }

#endif
