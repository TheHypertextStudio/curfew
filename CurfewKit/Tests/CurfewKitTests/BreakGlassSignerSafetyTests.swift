import CurfewKit
import Foundation
import Testing

struct BreakGlassSignerSafetyTests {
    @Test("Verification never creates a missing signing key")
    func verificationDoesNotProvision() throws {
        try withSigningFixture { directory in
            let secret = directory.appendingPathComponent("secret")
            var release = signingRelease()
            release.signature = String(repeating: "0", count: 64)
            #expect(!BreakGlassSigner.verify(release, secretURL: secret))
            #expect(!FileManager.default.fileExists(atPath: secret.path))
        }
    }

    @Test("Signing and verification preserve an invalid existing secret")
    func invalidSecretIsNotRotated() throws {
        try withSigningFixture { directory in
            let secret = directory.appendingPathComponent("secret")
            let original = Data("invalid key".utf8)
            try original.write(to: secret)
            var release = signingRelease()
            #expect(BreakGlassSigner.sign(release, secretURL: secret) == nil)
            #expect(try Data(contentsOf: secret) == original)
            release.signature = String(repeating: "0", count: 64)
            #expect(!BreakGlassSigner.verify(release, secretURL: secret))
            #expect(try Data(contentsOf: secret) == original)
        }
    }

    @Test("An unsafe signing-key symlink is rejected without replacing it")
    func unsafeSecretIsNotReplaced() throws {
        try withSigningFixture { directory in
            let target = directory.appendingPathComponent("target")
            let original = Data(repeating: 42, count: 32)
            try original.write(to: target)
            let secret = directory.appendingPathComponent("secret")
            try FileManager.default.createSymbolicLink(at: secret, withDestinationURL: target)
            #expect(BreakGlassSigner.sign(signingRelease(), secretURL: secret) == nil)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: secret.path) == target
                .path)
            #expect(try Data(contentsOf: target) == original)
        }
    }

    @Test("Parallel first signatures share one complete private key")
    func concurrentProvisioning() throws {
        try withSigningFixture { directory in
            for iteration in 0 ..< 12 {
                let secret = directory.appendingPathComponent("secret-\(iteration)")
                let gate = DispatchSemaphore(value: 0)
                let group = DispatchGroup()
                let signatures = SignatureResults()
                let release = signingRelease()
                for _ in 0 ..< 2 {
                    group.enter()
                    DispatchQueue.global().async {
                        gate.wait()
                        signatures.append(BreakGlassSigner.sign(release, secretURL: secret))
                        group.leave()
                    }
                }
                gate.signal()
                gate.signal()
                #expect(group.wait(timeout: .now() + 5) == .success)
                #expect(signatures.values.count == 2)
                for signature in signatures.values {
                    var signed = release
                    signed.signature = signature
                    #expect(BreakGlassSigner.verify(signed, secretURL: secret))
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: secret.path)
                #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
                #expect(try Data(contentsOf: secret).count == 32)
            }
        }
    }
}

private func signingRelease() -> BreakGlassRelease {
    BreakGlassRelease(
        issuedAt: Date(timeIntervalSince1970: 1_800_000_000),
        reason: "recover a stalled lockout",
        issuedBy: "tester@host"
    )
}

private func withSigningFixture(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private final class SignatureResults: @unchecked Sendable {
    private let lock = NSLock()
    private var signatures: [String?] = []
    var values: [String?] {
        lock.withLock { signatures }
    }

    func append(_ signature: String?) {
        lock.withLock { signatures.append(signature) }
    }
}
