import CryptoKit
import Foundation

/// Minimal JSON scalar emitter.
///
/// `JSONEncoder` is not used for the record envelope because the hash chain
/// needs byte-for-byte reproducibility from a spec, and `JSONEncoder`'s
/// escaping and key ordering are implementation details Apple is free to
/// change. Hand-emitting a fixed key order with an explicit escape table is
/// the whole reason a third party can verify the chain.
enum AuditJSON {
    /// Serializes `text` as a JSON string literal, escaping the two mandatory
    /// characters, the control range, and nothing else. Forward slashes and
    /// non-ASCII are emitted verbatim as UTF-8.
    static func quote(_ text: String) -> String {
        var out = "\""
        out.reserveCapacity(text.utf8.count + 2)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// Formats audit timestamps as ISO-8601 with milliseconds and an explicit
/// numeric UTC offset (`2026-08-08T21:14:07.412-05:00`).
///
/// The offset is kept rather than normalized to `Z` because a curfew is a
/// wall-clock promise: an auditor reading "lockout started at 22:00" needs to
/// see the local hour the user actually experienced, and the offset is also
/// the only on-disk evidence of a timezone change mid-window.
public enum AuditTimestamp {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withFullDate,
            .withTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime,
            .withTimeZone,
            .withColonSeparatorInTimeZone,
            .withFractionalSeconds
        ]
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let lock = NSLock()

    /// Renders `date` in the current timezone. Serialized behind a lock
    /// because `ISO8601DateFormatter` is not thread-safe and the daemon may
    /// format from a different thread than the app.
    public static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        lock.lock()
        defer { lock.unlock() }
        formatter.timeZone = timeZone
        let text = formatter.string(from: date)
        // `ISO8601DateFormatter` writes `Z` for UTC. Both spellings are valid
        // ISO-8601, but the audit format promises exactly one shape so a
        // hand-written parser can slice the offset at a fixed position
        // instead of branching.
        return text.hasSuffix("Z") ? String(text.dropLast()) + "+00:00" : text
    }
}

/// The genesis `prev` value for a stream that has never been written: 64
/// ASCII zeros, the same width as a SHA-256 hex digest.
public let auditGenesisHash = String(repeating: "0", count: 64)

/// Turns an ``AuditRecord`` into exactly one line of the on-disk format, and
/// verifies lines produced earlier.
///
/// The hash chain is defined entirely in terms of the emitted bytes:
///
/// 1. Serialize the record with keys in the fixed order
///    `v, ts, seq, stream, actor, event, from, to, detail, prev`,
///    omitting `from` and `to` when nil and `detail` when empty. Call the
///    resulting UTF-8 bytes the *body*, which ends in `}`.
/// 2. `hash` = lowercase hex SHA-256 of the body **including** its final `}`.
/// 3. The written line is the body with `,"hash":"<hash>"` spliced in before
///    that final `}`, followed by `\n`.
///
/// A verifier therefore recovers the body by deleting the final
/// `,"hash":"<64 hex>"` substring, and recomputes. See
/// `Documentation/audit-log.md` for the same rules stated for non-Swift
/// implementers.
public enum AuditLineEncoder {
    /// Serializes `record` chained to `previousHash` and returns both the
    /// line (with trailing newline) and the hash a following record must
    /// carry as its `prev`.
    public static func encode(
        _ record: AuditRecord,
        previousHash: String,
        timeZone: TimeZone = .current
    ) -> (line: String, hash: String) {
        let body = body(for: record, previousHash: previousHash, timeZone: timeZone)
        let hash = sha256Hex(body)
        // Splice rather than re-serialize: the hash must cover the exact
        // bytes a verifier will reconstruct, so the body string is the only
        // input either side is allowed to hash.
        let spliced = String(body.dropLast()) + ",\"hash\":" + AuditJSON.quote(hash) + "}"
        return (spliced + "\n", hash)
    }

    /// Recomputes the hash for an already-written `line` and compares it with
    /// the `hash` the line carries. Returns `false` for a malformed line, so a
    /// truncated final record from a crash reads as a chain break rather than
    /// as valid.
    public static func verify(line: String) -> Bool {
        guard let (body, claimed) = split(line: line) else { return false }
        return sha256Hex(body) == claimed
    }

    /// Extracts the `hash` field from a written line without validating it.
    /// Used by the writer to recover the chain head after a restart.
    public static func hash(inLine line: String) -> String? {
        split(line: line)?.claimed
    }

    /// Splits a written line into the body a verifier must hash and the hash
    /// the line claims.
    private static func split(line: String) -> (body: String, claimed: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("\"}") else { return nil }
        guard let marker = trimmed.range(of: ",\"hash\":\"", options: .backwards) else {
            return nil
        }
        let claimed = String(trimmed[marker.upperBound...].dropLast(2))
        guard claimed.count == 64 else { return nil }
        return (String(trimmed[trimmed.startIndex ..< marker.lowerBound]) + "}", claimed)
    }

    private static func body(
        for record: AuditRecord,
        previousHash: String,
        timeZone: TimeZone
    ) -> String {
        var parts: [String] = [
            "\"v\":\(auditSchemaVersion)",
            "\"ts\":" + AuditJSON.quote(AuditTimestamp.string(
                from: record.timestamp,
                timeZone: timeZone
            )),
            "\"seq\":\(record.sequence)",
            "\"stream\":" + AuditJSON.quote(record.stream.rawValue),
            "\"actor\":" + AuditJSON.quote(record.actor.token),
            "\"event\":" + AuditJSON.quote(record.event.rawValue)
        ]
        if let from = record.from {
            parts.append("\"from\":" + AuditJSON.quote(from))
        }
        if let to = record.to {
            parts.append("\"to\":" + AuditJSON.quote(to))
        }
        if !record.detail.isEmpty {
            parts.append("\"detail\":" + detailObject(record.detail))
        }
        parts.append("\"prev\":" + AuditJSON.quote(previousHash))
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Emits `detail` with keys in ascending Unicode order so two runs that
    /// build the same dictionary produce the same bytes.
    private static func detailObject(_ detail: [String: AuditValue]) -> String {
        let pairs = detail.keys.sorted().map { key in
            AuditJSON.quote(key) + ":" + (detail[key]?.jsonFragment ?? "null")
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Redaction helpers for text Curfew must never copy into the audit log.
///
/// The rule the codebase follows: the audit log records *that* the user wrote
/// a justification and how long it was, never the words. The words already
/// live in `activity.sqlite3`, which the retrospective owns and which the
/// privacy policy already accounts for. Copying them into a second, plain-text,
/// shareable file would widen the blast radius of "send me your Curfew logs"
/// for no auditing benefit — the decision is auditable from the length, the
/// digest, and the grant that followed.
public enum AuditRedaction {
    /// Truncated lowercase hex SHA-256 of `text`, or `nil` for empty input.
    ///
    /// 16 hex characters (64 bits) is enough to correlate an audit line with a
    /// row in `activity.sqlite3` and far too little to be worth a rainbow
    /// table for the ≥50-character prose the override composer requires. No
    /// salt: a salt would have to be stored somewhere, and the only threat it
    /// would close is brute-forcing short strings that this field never holds.
    public static func digest(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let full = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(full.prefix(16))
    }

    /// `detail` entries describing a redacted string: its character count and
    /// its digest, under `<prefix>Length` and `<prefix>Digest`.
    public static func redactedDetail(
        _ text: String,
        prefix: String
    ) -> [String: AuditValue] {
        var detail: [String: AuditValue] = [prefix + "Length": .int(text.count)]
        if let digest = digest(text) {
            detail[prefix + "Digest"] = .string(digest)
        }
        return detail
    }
}
