import CurfewKit
import Foundation
import ScreenSaver

/// Module-specific companion exchange. Intentionally inert pending observed RED.
/// Inject isolated defaults in tests; only the explicit system factory may open the saver domain.
public final class RestScreenSaverPreferences {
    public static let moduleIdentifier = "studio.hypertext.apps.curfew.screensaver"

    enum Keys {
        static let appearance = "rest.presentation.v1.appearance"
        static let occurrence = "rest.presentation.v1.occurrence"
        static let readbackRequest = "rest.presentation.v1.readbackRequest"
        static let acknowledgement = "rest.presentation.v1.acknowledgement"
    }

    public enum AdapterError: Error {
        case awaitingFailingTest
    }

    public init(
        defaults: UserDefaults,
        inspectImageHeader: @escaping (Data) throws -> RestCompanionExport.ImageDimensions =
            RestScreenSaverPreferences.inspectImageHeader
    ) {}

    /// SDK ScreenSaverDefaults.h declares +defaultsForModuleWithName: (nullable instancetype).
    /// Intended Swift call: ScreenSaverDefaults(forModuleWithName: Self.moduleIdentifier).
    /// No production domain is opened until implementation is authorized after RED.
    public static func system() throws -> RestScreenSaverPreferences {
        throw AdapterError.awaitingFailingTest
    }

    public func publish(snapshot: RestSceneSnapshot, imageData: Data?) throws {
        throw AdapterError.awaitingFailingTest
    }

    public func read(at date: Date) -> RestCompanionPresentationStore.Publication? {
        nil
    }

    public func requestReadback() throws -> UUID {
        throw AdapterError.awaitingFailingTest
    }

    public func acknowledge(_ publication: RestCompanionPresentationStore.Publication) throws {
        throw AdapterError.awaitingFailingTest
    }

    public func hasAcknowledgedCurrentPublication() -> Bool {
        false
    }

    /// Implementation must bound encoded bytes and read ImageIO properties without pixel decode.
    public static func inspectImageHeader(
        _ bytes: Data
    ) throws -> RestCompanionExport.ImageDimensions {
        throw AdapterError.awaitingFailingTest
    }
}
