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
    /// Taken from `curfew-sync/Documentation/ARCHITECTURE.md` §"API surface",
    /// which lists `POST /sync/heartbeat` as the HTTP status-report path for
    /// devices not holding a WebSocket open, alongside `GET /sync/socket` for
    /// those that are. It is the only device status-report path any authority
    /// in the three repos actually names.
    ///
    /// Neither this path nor any other is implemented in curfew-sync today —
    /// `src/plugins/device-sync.ts` declares `endpoints: {}` — so this constant
    /// is unverified against a running server and is the single line to change
    /// when the coordinator's route lands under a different name.
    public static let statusPath = "sync/heartbeat"

    /// Narrowest and widest heartbeat cadence Curfew will honour. A minute is
    /// as often as a status report can say anything new given enforcement moves
    /// in minutes; an hour is the point past which a coordinator would call the
    /// device offline anyway.
    public static let heartbeatFloorSeconds = 60
    /// See ``heartbeatFloorSeconds``.
    public static let heartbeatCeilingSeconds = 3600

    /// Whether Curfew may publish status at all. **Off unless the user turned
    /// it on**, and the only thing that permits a network request to exist.
    public var isEnabled: Bool

    /// The coordinator's base URL, as the user typed it. Empty by default.
    public var baseURL: String

    /// The device credential issued at enrollment, sent as an HTTP bearer
    /// token. Empty by default.
    ///
    /// curfew-sync's documented device-agent auth is a device session cookie
    /// issued by `POST /sync/enroll/start`, and enrollment is not implemented
    /// on either side yet. A user-pasted bearer token is the least-invented
    /// stand-in available: it is a standard HTTP mechanism rather than a coined
    /// wire shape, and it is a stand-in — the real credential exchange belongs
    /// with the enrollment work.
    public var deviceToken: String

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
        case deviceToken
        case deviceID
        case heartbeatSeconds
    }

    /// Memberwise initialiser. ``heartbeatSeconds`` is clamped on assignment so
    /// an out-of-range value written directly to the struct is corrected rather
    /// than persisted.
    public init(
        isEnabled: Bool,
        baseURL: String,
        deviceToken: String,
        deviceID: String,
        heartbeatSeconds: Int
    ) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.deviceToken = deviceToken
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
        let deviceToken = try container.decodeIfPresent(
            String.self,
            forKey: .deviceToken
        ) ?? fallback.deviceToken
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
            deviceToken: deviceToken,
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
    /// device identifier**, five-minute heartbeat for whenever the user turns
    /// it on.
    public static let `default` = DeviceStatusReportingPolicy(
        isEnabled: false,
        baseURL: "",
        deviceToken: "",
        deviceID: "",
        heartbeatSeconds: 300
    )
}
