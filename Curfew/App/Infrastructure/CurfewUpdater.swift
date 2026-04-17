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

        @Published private(set) var canCheckForUpdates = false

        init() {
            self.controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.canCheckForUpdates = controller.updater.canCheckForUpdates
        }

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
        @Published private(set) var canCheckForUpdates = false
        nonisolated init() {}
        func checkForUpdates() {}
    }

#endif
