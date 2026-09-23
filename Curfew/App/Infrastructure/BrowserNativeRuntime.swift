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
    private var acceptsPolicyCallbacks = false
    private let startupIsAllowed: () -> Bool
    private let installForStartup: (() throws -> Void)?
    private let flavor: CurfewFlavor
    private(set) var installationError: String?
    private(set) var enforcementEnabled = false

    init(
        store: BrowserNativeStore = BrowserNativeStore(),
        coordinator: DocketBrowserPolicyCoordinator? = nil,
        flavor: CurfewFlavor = .current,
        startupIsAllowed: (() -> Bool)? = nil,
        installForStartup: (() throws -> Void)? = nil
    ) {
        self.store = store
        self.flavor = flavor
        self.coordinator = coordinator ?? DocketBrowserPolicyCoordinator()
        self.startupIsAllowed = startupIsAllowed ?? {
            !RuntimeEnvironment.isUnitTestHost &&
                ProcessInfo.processInfo.environment["CURFEW_DEMO_FIXTURE"] != "1"
        }
        self.installForStartup = installForStartup
        if let record = try? store.readPolicy(),
           let policy = record.policy,
           let identity = record.retainedSessionIdentity,
           identity.sessionID == policy.sessionID {
            self.coordinator.restoreRetainedSessionIdentity(identity)
        }
        self.coordinator.onPolicyChanged = { [weak self] policy in
            guard let self, !stopped, acceptsPolicyCallbacks else { return }
            do {
                try publishPolicy(
                    enforcementEnabled ? policy : nil,
                    allowClearingRetainedPolicy: !enforcementEnabled
                )
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
        guard flavor != .studioDevelopment, maintenance == nil, startupIsAllowed() else { return }
        do {
            if let installForStartup {
                try installForStartup()
            } else {
                try install()
            }
            try publishPolicy(
                enforcementEnabled ? coordinator.policy(at: Date()) : nil,
                allowClearingRetainedPolicy: !enforcementEnabled
            )
            acceptsPolicyCallbacks = true
            stopped = false
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
            stopped = true
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
        acceptsPolicyCallbacks = false
        coordinator.stopPolling()
    }

    func install() throws {
        guard flavor != .studioDevelopment else { throw BrowserNativeError.invalidIdentity }
        let extensionID = flavor == .development
            ? BrowserNativeInstallation.developmentExtensionID
            : Bundle.main.object(forInfoDictionaryKey: "CurfewBrowserExtensionID") as? String ?? ""
        try BrowserNativeInstallation.install(
            extensionID: extensionID,
            executable: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/studio.hypertext.curfew.browser"),
            flavor: flavor
        )
        installationError = nil
    }

    func health(at date: Date) -> BrowserNativeHealth? {
        try? store.health(at: date)
    }

    func isInstalled() -> Bool {
        (try? store.isActive()) == true
    }

    func configureEnforcementForStartup(_ enabled: Bool) {
        enforcementEnabled = enabled
    }

    func setEnforcementEnabled(_ enabled: Bool, at date: Date = Date()) throws {
        try publishPolicy(
            enabled ? coordinator.policy(at: date) : nil,
            at: date,
            allowClearingRetainedPolicy: !enabled
        )
        enforcementEnabled = enabled
        acceptsPolicyCallbacks = true
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
                try publishPolicy(
                    enforcementEnabled ? coordinator.policy(at: Date()) : nil,
                    allowClearingRetainedPolicy: !enforcementEnabled
                )
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

    private func publishPolicy(
        _ policy: BrowserPolicySnapshot?,
        at date: Date = Date(),
        allowClearingRetainedPolicy: Bool = false
    ) throws {
        // A new coordinator has no in-memory session. An outage or idle first
        // poll cannot prove that the signed session from the last run ended.
        if policy == nil, !allowClearingRetainedPolicy,
           !coordinator.hasConfirmedPolicyObservation,
           !coordinator.hasConfirmedRetainedSessionEnd,
           try store.readPolicy()?.policy != nil {
            return
        }
        try store.writePolicy(
            policy,
            retainedSessionIdentity: coordinator.retainedSessionIdentity,
            at: date
        )
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
