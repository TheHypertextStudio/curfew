import AppKit
import CurfewKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "studio.hypertext.curfew", category: "supervisor")

@MainActor
private final class Supervisor {
    private let appURL: URL
    private let bundleIdentifier: String
    private var policy = AppSupervisorPolicy()
    private var activeLaunch: UUID?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private let healthStore = SupervisorHealthStore.production()
    private var launchFailure: String?

    init(appURL: URL, bundleIdentifier: String) {
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard app.bundleIdentifier == self?.bundleIdentifier else { return }
                self?.reconcile()
            }
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        reconcile()
    }

    private func reconcile() {
        let isRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).contains { !$0.isTerminated }
        if isRunning {
            launchFailure = nil
        }
        recordHealth()
        guard policy.shouldLaunch(at: Date(), appIsRunning: isRunning) else { return }
        let launch = UUID()
        activeLaunch = launch
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.arguments = ["--background"]
        #if CURFEW_STAGING
            if Bundle(url: appURL)?
                .object(forInfoDictionaryKey: "CurfewAcceptanceFixture") as? Bool == true {
                configuration.arguments.append("--supervisor-acceptance")
                if let path = Bundle(url: appURL)?.object(
                    forInfoDictionaryKey: "CurfewAcceptanceReportPath"
                ) as? String {
                    configuration.environment["CURFEW_ACCEPTANCE_REPORT"] = path
                }
            }
        #endif
        NSWorkspace.shared
            .openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.completeLaunch(launch, error: error)
                }
            }
        // A lost workspace callback must not leave recovery permanently blocked.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.completeLaunch(launch, error: CocoaError(.executableLoad))
        }
    }

    private func recordHealth() {
        do {
            try healthStore.save(SupervisorHealthRecord(
                lastCheckedAt: Date(), launchFailure: launchFailure
            ))
        } catch {
            logger
                .error(
                    "Supervisor health write failed: \(error.localizedDescription, privacy: .public)"
                )
        }
    }

    private func completeLaunch(_ launch: UUID, error: Error?) {
        guard activeLaunch == launch else { return }
        activeLaunch = nil
        policy.launchCompleted(at: Date())
        launchFailure = error?.localizedDescription
        recordHealth()
        if let error {
            logger.error("Curfew launch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

let expectedIdentifier = CurfewFlavor.current.bundleIdentifier
guard let executableURL = SupervisorBundleLocation.executableURL(),
      let appURL = SupervisorBundleLocation.enclosingApplication(executableURL: executableURL),
      Bundle(url: appURL)?.bundleIdentifier == expectedIdentifier else {
    logger.error("Supervisor is outside its matching Curfew bundle")
    exit(78)
}

private let supervisor = MainActor.assumeIsolated {
    let supervisor = Supervisor(appURL: appURL, bundleIdentifier: expectedIdentifier)
    supervisor.start()
    return supervisor
}

RunLoop.main.run()
