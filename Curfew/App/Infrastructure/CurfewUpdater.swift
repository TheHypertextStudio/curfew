import Combine
import Foundation
import SwiftUI

// Sparkle autoupdate integration.
//
// The feed URL and a placeholder public EdDSA key already ship in the app's
// build settings (INFOPLIST_KEY_SUFeedURL / INFOPLIST_KEY_SUPublicEDKey), so
// the only remaining steps to light this up are:
//   1. In Xcode → File → Add Package Dependencies, add:
//      https://github.com/sparkle-project/Sparkle  (exact 2.x).
//      Link Sparkle into the Curfew target.
//   2. Run scripts/gen-sparkle-keypair.sh to mint an EdDSA key pair.
//      Paste the public key into INFOPLIST_KEY_SUPublicEDKey (replacing the
//      REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY placeholder) and store the private
//      key as the SPARKLE_PRIVATE_KEY repo secret for the appcast signer.
//
// The live path below is gated on `#if canImport(Sparkle)` — not a custom
// compilation flag — so the moment the package is linked the real updater and
// the Check for Updates… menu item come online with no further code changes.
// Until then `CurfewUpdater` falls back to a no-op stub so the rest of the
// project compiles and the menu item stays hidden.

#if canImport(Sparkle)

    import Sparkle

    /// Live updater backed by Sparkle.
    @MainActor
    final class CurfewUpdater: ObservableObject {
        static let isAvailable = true

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
    /// project. With `isAvailable == false`, `CurfewApp` omits the Check for
    /// Updates… menu item entirely, so this stub is never invoked.
    @MainActor
    final class CurfewUpdater: ObservableObject {
        static let isAvailable = false

        /// Always `false` in the stub; the menu item is hidden, so it is unused.
        @Published private(set) var canCheckForUpdates = false
        /// No-op init.
        nonisolated init() {}
        /// No-op; the menu item is hidden when Sparkle is unlinked, so this
        /// never fires.
        func checkForUpdates() {}
    }

#endif
