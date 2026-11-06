import Darwin
import Foundation

/// A completed atomic command remains committed after the first interruption.
final class CLIInterrupts {
    private let lock = NSLock()
    private let message: (String) -> Void
    private let forceExit: (Int32) -> Void
    private var status: Int32?
    private var sources: [any DispatchSourceSignal] = []
    private var previousInterrupt: sig_t?
    private var previousTerminate: sig_t?

    init(message: @escaping (String) -> Void, forceExit: @escaping (Int32) -> Void) {
        self.message = message
        self.forceExit = forceExit
    }

    var exitStatus: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func receive(_ signal: Int32) {
        lock.lock()
        let repeated = status != nil
        let code = status ?? 128 + signal
        status = code
        lock.unlock()
        if repeated {
            message("Stopped immediately. Completed changes were kept.")
            forceExit(code)
        } else {
            message("Stopping after the current step. Press Ctrl+C again to stop now.")
        }
    }

    func start() {
        previousInterrupt = signal(SIGINT, SIG_IGN)
        previousTerminate = signal(SIGTERM, SIG_IGN)
        for number in [SIGINT, SIGTERM] {
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                for _ in 0 ..< max(1, source.data) {
                    self?.receive(number)
                }
            }
            sources.append(source)
            source.resume()
        }
    }

    func stop() {
        for source in sources {
            source.setEventHandler(handler: nil)
            source.cancel()
        }
        sources.removeAll()
        if let previousInterrupt {
            signal(SIGINT, previousInterrupt)
        }
        if let previousTerminate {
            signal(SIGTERM, previousTerminate)
        }
    }
}
