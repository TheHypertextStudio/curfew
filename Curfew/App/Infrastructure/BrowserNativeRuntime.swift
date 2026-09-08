import Foundation
import OSLog

private let browserLogger = Logger(subsystem: "studio.hypertext.curfew", category: "browser")

@MainActor
final class BrowserNativeRuntime {
    let coordinator: DocketBrowserPolicyCoordinator
    private let store: BrowserNativeStore
    private var source: DispatchSourceFileSystemObject?
    private var maintenance: Task<Void, Never>?
    private var processing = false
    private var stopped = false
    private(set) var installationError: String?

    init(
        store: BrowserNativeStore = BrowserNativeStore(),
        coordinator: DocketBrowserPolicyCoordinator? = nil
    ) {
        self.store = store
        self.coordinator = coordinator ?? DocketBrowserPolicyCoordinator()
        self.coordinator.onPolicyChanged = { [weak self] policy in
            guard let self, !stopped else { return }
            do {
                try publishPolicy(policy)
            } catch {
                browserLogger.error("Browser policy snapshot could not be saved.")
            }
        }
    }

    deinit {
        source?.cancel()
        maintenance?.cancel()
    }

    func start() {
        guard maintenance == nil, !RuntimeEnvironment.isUnitTestHost,
              ProcessInfo.processInfo.environment["CURFEW_DEMO_FIXTURE"] != "1"
        else { return }
        stopped = false
        do {
            try install()
            watchDirectory()
            coordinator.startPolling()
            maintenance = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await processPending()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        } catch {
            installationError = "Chrome browser integration could not be installed."
            browserLogger.error("Browser integration installation failed.")
        }
    }

    func stop() {
        stopped = true
        source?.cancel()
        source = nil
        maintenance?.cancel()
        maintenance = nil
        coordinator.stopPolling()
    }

    func install() throws {
        let extensionID = CurfewFlavor.current == .development
            ? BrowserNativeInstallation.developmentExtensionID
            : Bundle.main.object(forInfoDictionaryKey: "CurfewBrowserExtensionID") as? String ?? ""
        try BrowserNativeInstallation.install(
            extensionID: extensionID,
            executable: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/studio.hypertext.curfew.browser")
        )
        installationError = nil
    }

    func health(at date: Date) -> BrowserNativeHealth? {
        try? store.health(at: date)
    }

    func processPending() async {
        guard !processing, !stopped else { return }
        processing = true
        defer { processing = false }
        do {
            try store.prune(at: Date())
            for entry in try store.pending(at: Date()) {
                guard let destination = entry.request.destination else { continue }
                let result = await coordinator.review(
                    rawDestination: destination.origin + destination.path,
                    justification: entry.request.justification ?? "",
                    challengeAnswer: entry.request.challengeAnswer,
                    at: Date(), expectedSessionID: entry.request.sessionID,
                    requestIsFresh: { [store] in
                        entry
                            .isFresh(at: Date()) &&
                            (try? store.pending(at: Date()).contains { $0.id == entry.id }) == true
                    }
                )
                let response = Self.response(result)
                guard !stopped else { return }
                try publishPolicy(coordinator.policy(at: Date()))
                try store.resolve(id: entry.id, result: response, at: Date())
                let hostname = destination.reviewURL.host ?? ""
                let kind = response.scope?.kind.rawValue ?? "none"
                browserLogger
                    .info(
                        "\(hostname, privacy: .public) \(response.decision, privacy: .public) \(kind, privacy: .public)"
                    )
            }
        } catch {
            browserLogger.error("Browser request queue could not be processed.")
        }
    }

    private func publishPolicy(_ policy: BrowserPolicySnapshot?) throws {
        // A new coordinator has no in-memory session. An outage or idle first
        // poll cannot prove that the signed session from the last run ended.
        if policy == nil, !coordinator.hasConfirmedPolicyObservation,
           try store.readPolicy()?.policy != nil {
            return
        }
        try store.writePolicy(policy, at: Date())
    }

    private func watchDirectory() {
        let descriptor = open(store.directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in await self?.processPending() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private static func response(_ review: DocketDestinationReview) -> BrowserNativeReviewResult {
        switch review {
        case .grant(let reason, let scope): .init(decision: "grant", reason: reason, scope: scope)
        case .challenge(let reason, let question): .init(
                decision: "challenge",
                reason: reason,
                question: question
            )
        case .deny(let reason): .init(decision: "deny", reason: reason)
        }
    }
}
