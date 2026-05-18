import Foundation

/// Rotating catalogue of short affirmations shown on the lockout screen.
///
/// Copy is intentionally warm rather than preachy — the user already opted
/// into curfew; they don't need to be lectured when lockout fires. The
/// rotation is deterministic (index-based, not random) so a user who sees
/// message N today sees message N+1 tomorrow. This reduces the feel of the
/// lockout screen being repetitive.
///
/// Messages live here rather than in a localisation bundle because v0.1 is
/// English-only. When localisation lands in v0.2, swap the `messages` array
/// for `String.localizedStringWithFormat` calls keyed off a resource table.
enum EncouragementMessageCatalog {
    /// Pool of lockout screen messages. Order matters: `next(after:)` walks
    /// the list circularly, so edits should preserve the tone progression.
    static let messages = [
        "Great work today. Tomorrow is another day.",
        "The best code is written by a rested mind.",
        "You've earned this. Go live your life.",
        "Nothing in your inbox is more important than your health.",
        "Future you will be grateful."
    ]

    /// Message shown after the user successfully confirms an override and
    /// regains temporary access. Not part of the rotation — we don't want
    /// to "reward" overrides with fresh encouragement the way first-entry
    /// into lockout gets rotated copy.
    static let postOverride = "Welcome back. Hope you got what you needed."

    /// Returns the next message after `previous`, wrapping around when the
    /// end of the list is reached. When `previous` is `nil` or unknown (e.g.
    /// the catalogue was edited between sessions and the stored prior
    /// message no longer exists), returns the first entry.
    ///
    /// - Parameter previous: the message shown last time lockout began, or
    ///   `nil` on first launch.
    /// - Returns: a message to display; guaranteed non-empty as long as
    ///   `messages` is non-empty (see fallback).
    static func next(after previous: String?) -> String {
        guard let previous, let index = messages.firstIndex(of: previous), !messages.isEmpty else {
            return messages.first ?? "Great work today."
        }
        let nextIndex = (index + 1) % messages.count
        return messages[nextIndex]
    }
}
