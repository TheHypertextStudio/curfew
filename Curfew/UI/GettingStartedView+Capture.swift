import CurfewKit
import SwiftUI

#if DEBUG
    extension GettingStartedView {
        /// Capture builds only: with `CURFEW_DEMO_SETUP_WALKTHROUGH=1` the demo
        /// fixture walks through setup by itself, so the whole first run can be
        /// recorded without a pointer or focus. The fixture already trusts
        /// Accessibility and never arms enforcement.
        func runCaptureWalkthrough() async {
            let environment = ProcessInfo.processInfo.environment
            guard model.isDemoSession, isLive,
                  environment["CURFEW_DEMO_SETUP_WALKTHROUGH"] == "1" else { return }
            func pause(_ seconds: Double) async {
                try? await Task.sleep(for: .seconds(seconds))
            }
            func nudge(_ field: SetupScheduleDraft.Field, by minutes: Int) async {
                for _ in 0 ..< 2 {
                    withAnimation(.snappy(duration: 0.25)) {
                        draft = draftBinding.wrappedValue.adjusting(field, by: minutes)
                    }
                    await pause(0.6)
                }
            }
            await pause(SetupSky.Intro.duration + 2.5)
            change { flow.begin() }
            await pause(3.4)
            await nudge(.curfew, by: 15)
            await pause(0.8)
            change { editingMorning = true }
            await pause(3.4)
            await nudge(.unlock, by: -15)
            await pause(0.8)
            change { editingMorning = false }
            await pause(3.2)
            if let draft {
                model.applySetupSchedule(draft)
            }
            change { flow.chooseSchedule(.weeklySchedule) }
            await pause(2.6)
            continueFromPermissions(showsGrant: true)
            await pause(3.4)
            notificationStatus = .allowed
            await pause(1.4)
            change { flow.advance() }
            await pause(5)
            change { flow.advance() }
        }
    }
#endif
