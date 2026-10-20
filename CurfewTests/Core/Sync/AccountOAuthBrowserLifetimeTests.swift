import AppKit
import AuthenticationServices
@testable import Curfew
import CurfewKit
import Foundation
import XCTest

@MainActor
final class AccountOAuthBrowserLifetimeTests: XCTestCase {
    func testLateBrowserCompletionCannotEndTheNextSignIn() async throws {
        _ = NSApplication.shared
        let window = NSWindow()
        let firstStarted = expectation(description: "first browser started")
        let secondStarted = expectation(description: "replacement browser started")
        var browsers: [DeferredOAuthBrowserSession] = []
        let service = AccountOAuthEnrollmentService(
            secretStore: NativeTransportMemorySecretStore(),
            endpoints: .staging,
            callbackRouter: AccountOAuthCallbackRouter(),
            browserSessionFactory: { url, callback, completion in
                let browser = DeferredOAuthBrowserSession(
                    url: url,
                    callback: callback,
                    completion: completion,
                    started: browsers.isEmpty ? firstStarted : secondStarted
                )
                browsers.append(browser)
                return browser
            }
        )
        let first = Task {
            try await service.signIn(presentationWindow: window) { _ in }
        }
        await fulfillment(of: [firstStarted], timeout: 5)
        let firstBrowser = try XCTUnwrap(browsers.first)
        firstBrowser.complete(error: NSError(domain: "first-browser", code: 1))
        do {
            _ = try await first.value
            XCTFail("The first browser was cancelled")
        } catch {
            XCTAssertEqual((error as NSError).domain, "first-browser")
        }

        let second = Task {
            try await service.signIn(presentationWindow: window) { _ in }
        }
        await fulfillment(of: [secondStarted], timeout: 5)
        let secondBrowser = try XCTUnwrap(browsers.last)
        firstBrowser.complete(error: NSError(domain: "late-cancelled-browser", code: 2))
        secondBrowser.complete(error: NSError(domain: "current-browser", code: 3))

        do {
            _ = try await second.value
            XCTFail("The current browser returned its own error")
        } catch {
            XCTAssertEqual((error as NSError).domain, "current-browser")
        }
    }
}

@MainActor
private final class DeferredOAuthBrowserSession: ASWebAuthenticationSession {
    private let completion: ASWebAuthenticationSession.CompletionHandler
    private let started: XCTestExpectation

    init(
        url: URL,
        callback: ASWebAuthenticationSession.Callback,
        completion: @escaping ASWebAuthenticationSession.CompletionHandler,
        started: XCTestExpectation
    ) {
        self.completion = completion
        self.started = started
        super.init(url: url, callback: callback, completionHandler: completion)
    }

    override func start() -> Bool {
        started.fulfill()
        return true
    }

    override func cancel() {}

    func complete(error: Error) {
        completion(nil, error)
    }
}
