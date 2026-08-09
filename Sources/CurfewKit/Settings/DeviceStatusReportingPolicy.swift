import Foundation

/// User settings for publishing this device's status to a curfew-sync
/// coordinator.
///
/// The important line in this file is ``default``: ``isEnabled`` is `false` and
/// ``baseURL`` is empty. A fresh install, a restored backup, a settings blob
/// written by a build that had never heard of this struct, and a corrupted
/// preferences file all resolve to a Curfew that talks to nobody. Every decode
/// path below falls back to ``default`` for that reason.
///
/// **No coordinator address is compiled in.** There is no default host, no
/// staging fallback, no "if empty, use ours". The endpoint is a customer's
/// configuration, entered in Curfew's own Settings window; a hostname constant
/// in domain code would make one person's deployment everybody's default.
public struct DeviceStatusReportingPolicy: Codable, Equatable, Sendable {
    /// The path appended to ``baseURL`` to form the publish endpoint.
    ///
    /// `POST /sync/status`, the route curfew-sync actually implements:
    /// `src/routes/device-status.ts` mounted at `/sync` by `src/worker.ts`.
    /// It parses the body as `sync.json#/definitions/DeviceStatusPublication`
    /// and answers `204` on acceptance, `409` on a stale `statusVersion`.
    ///
    /// Not `sync/heartbeat`, which `curfew-sync/Documentation/ARCHITECTURE.md`
    /// §"API surface" lists as a *planned* liveness ping for devices that are
    /// not holding a WebSocket open. It is unimplemented, and its job — telling
    /// a coordinator this device is alive — is a strict subset of what a status
    /// publication already does. Two paths would be two things to keep true.
    public static let statusPath = "sync/status"

    /// Narrowest and widest heartbeat cadence Curfew will honour, both taken
    /// from the cadence `Documentation/curfew-sync.md` §"Sync model" documents
    /// for the device registry: **60 s active, 120 s freshness threshold**,
    /// reused from F14/F15.
    ///
    /// The floor is the documented active cadence, and also as often as a
    /// status report can say anything new given enforcement moves in minutes.
    /// The ceiling is the freshness threshold, and it is a real bound rather
    /// than a round number: a device publishing less often than the coordinator
    /// waits before calling it stale reads as offline *between its own
    /// heartbeats*, which is worse than not reporting — it is reporting
    /// something false. So the settable range is exactly the range in which the
    /// contract holds.
    public static let heartbeatFloorSeconds = 60
    /// See ``heartbeatFloorSeconds``.
    public static let heartbeatCeilingSeconds = 120

    /// Whether Curfew may publish status at all. **Off unless the user turned
    /// it on**, and the only thing that permits a network request to exist.
    public var isEnabled: Bool

    /// The coordinator's base URL, as the user typed it. Empty by default.
    public var baseURL: String

    /// The coordinator account this device reports to. Empty by default.
    ///
    /// Becomes `userId` in the identity assertion Curfew signs for every
    /// request — `sync.json#/definitions/InternalDeviceIdentityClaims`, which
    /// constrains it to 1–128 characters and nothing else. `POST /sync/status`
    /// writes it onto the device row and `GET /sync/status` filters a reader's
    /// devices by it, so it is what makes two Macs show up as one person's
    /// rather than two accounts'.
    ///
    /// Not a secret, and deliberately stored beside the rest of the
    /// configuration: it names an account, it does not authenticate one. The
    /// thing that authenticates lives in the Keychain — see
    /// `DeviceAssertionSecretStore`.
    ///
    /// This replaces the pasted `deviceToken` an earlier build carried. That
    /// field was a stand-in for a credential exchange that had not been
    /// designed; the assertion is the designed one, and a pasted opaque token
    /// can never satisfy `verifyRequestAssertion`, so keeping the field would
    /// have meant a settings row that guarantees a 401.
    public var userID: String

    /// This install's device identifier, minted once and kept.
    ///
    /// A random UUID rather than the machine's `IOPlatformUUID`, so the value
    /// Curfew sends cannot be cross-referenced with any other software's idea
    /// of this Mac. Empty until the user first enables reporting.
    public var deviceID: String

    /// How often to publish when nothing has changed. Clamped on assignment.
    public var heartbeatSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case baseURL
        case userID
        case deviceID
        case heartbeatSeconds
    }

    /// Memberwise initialiser. ``heartbeatSeconds`` is clamped on assignment so
    /// an out-of-range value written directly to the struct is corrected rather
    /// than persisted.
    public init(
        isEnabled: Bool,
        baseURL: String,
        userID: String,
        deviceID: String,
        heartbeatSeconds: Int
    ) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.userID = userID
        self.deviceID = deviceID
        self.heartbeatSeconds = min(
            max(heartbeatSeconds, Self.heartbeatFloorSeconds),
            Self.heartbeatCeilingSeconds
        )
    }

    /// Decoder tolerant of a settings payload written before status reporting
    /// existed, which is every payload on every machine that upgrades into this
    /// release. `isEnabled` decodes with `decodeIfPresent ?? false`, so an
    /// upgrade can only ever land on reporting being off.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        let isEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? fallback.isEnabled
        let baseURL = try container.decodeIfPresent(
            String.self,
            forKey: .baseURL
        ) ?? fallback.baseURL
        let userID = try container.decodeIfPresent(
            String.self,
            forKey: .userID
        ) ?? fallback.userID
        let deviceID = try container.decodeIfPresent(
            String.self,
            forKey: .deviceID
        ) ?? fallback.deviceID
        let heartbeatSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .heartbeatSeconds
        ) ?? fallback.heartbeatSeconds
        self.init(
            isEnabled: isEnabled,
            baseURL: baseURL,
            userID: userID,
            deviceID: deviceID,
            heartbeatSeconds: heartbeatSeconds
        )
    }

    /// The endpoint to publish to, or `nil` when this policy does not describe
    /// a usable one.
    ///
    /// `nil` whenever reporting is off, the base URL is blank or unparseable,
    /// or the scheme is not HTTPS. The HTTPS requirement is not configurable:
    /// a status report names a device, its schedule digest, and when it is
    /// locked, and putting that on the wire in the clear would be a worse
    /// privacy outcome than not reporting at all.
    public var resolvedEndpoint: URL? {
        guard isEnabled else { return nil }
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let base = URL(string: trimmed),
              base.scheme?.lowercased() == "https",
              base.host?.isEmpty == false
        else { return nil }
        return base.appendingPathComponent(Self.statusPath)
    }

    /// Factory defaults: **reporting off, no endpoint, no credential, no
    /// device identifier**, and the documented 60-second active cadence for
    /// whenever the user turns it on.
    public static let `default` = DeviceStatusReportingPolicy(
        isEnabled: false,
        baseURL: "",
        userID: "",
        deviceID: "",
        heartbeatSeconds: Self.heartbeatFloorSeconds
    )
}
