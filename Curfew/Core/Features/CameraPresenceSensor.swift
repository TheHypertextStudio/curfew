import AVFoundation
import CoreVideo
import Foundation
import OSLog
import Vision

/// `nonisolated` because the app target compiles with
/// `-default-isolation=MainActor`, and every one of this logger's call sites is
/// inside ``CameraPresenceEngine``, which is deliberately off the main actor.
/// `Logger` is `Sendable`, so sharing one across actors is safe.
private nonisolated let presenceLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "presence-camera"
)

/// A source of "is a person in front of this Mac right now".
///
/// Behind a protocol for the usual testability reason and one unusual one: a
/// test that accidentally instantiated the real sensor would open the user's
/// camera. Every consumer in the app depends on this protocol, the production
/// conformance is constructed in exactly one place
/// (`CurfewAppModel+Presence.swift`), and the tests inject a fake — so there
/// is no path by which a unit run turns the light on.
///
/// Implementations must guarantee that ``stop()`` fully releases the capture
/// device. "Paused but still bound" is not an acceptable stopped state; the
/// camera indicator light going out is part of the contract.
@MainActor
protocol PersonPresenceSensing: AnyObject {
    /// Whether the user has granted camera access. Read-only — granting is
    /// the user's act, via ``requestAuthorization(completion:)``.
    var authorization: CameraAuthorization { get }

    /// Whether a capture session is currently running. `true` means the camera
    /// is on and the in-app indicator must say so.
    var isRunning: Bool { get }

    /// The most recent verdict and when it was taken.
    /// ``PersonObservation/never`` before the first analysed frame.
    var latestObservation: PersonObservation { get }

    /// Begins capture. Must be a no-op unless ``authorization`` permits it.
    func start()

    /// Ends capture and releases the camera. Must be safe to call when
    /// already stopped, and must reset ``latestObservation`` so a stale
    /// verdict cannot outlive the session that produced it.
    func stop()

    /// Asks macOS for camera access, then reports the resulting status on the
    /// main actor. Reports the current status unchanged when it is already
    /// decided, since macOS will not re-prompt.
    ///
    /// The completion is `@MainActor` because AVFoundation delivers its own
    /// callback on a private queue and every consumer of this result touches
    /// published model state; hopping once here beats every call site
    /// remembering to.
    func requestAuthorization(completion: @escaping @MainActor (CameraAuthorization) -> Void)
}

/// Production ``PersonPresenceSensing``.
///
/// A thin main-actor facade over ``CameraPresenceEngine``, which does all the
/// AVFoundation and Vision work off the main thread. The split exists because
/// `AVCaptureSession.startRunning()` blocks for up to a second and the tick
/// loop must never wait on it.
///
/// This layer owns the two refusals that keep the camera off when it should
/// be: an unauthorized start is dropped, and a start inside a unit-test host
/// is dropped. The engine below has no idea about either — it turns the camera
/// on when told, so the telling is gated here.
@MainActor
final class VisionCameraPresenceSensor: PersonPresenceSensing {
    private let engine = CameraPresenceEngine()

    /// Reads the live TCC status for video capture.
    var authorization: CameraAuthorization {
        Self.currentAuthorization
    }

    /// The process-wide camera authorization, readable without constructing a
    /// sensor. Reading TCC status neither prompts nor opens the device, so
    /// this is safe from any surface — including a Settings panel rendered
    /// before the model has ever ticked.
    static var currentAuthorization: CameraAuthorization {
        map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Whether the capture session is live.
    var isRunning: Bool {
        engine.isRunning
    }

    /// The most recent verdict, or ``PersonObservation/never``.
    var latestObservation: PersonObservation {
        engine.latestObservation
    }

    /// Opens the camera, unless it is unauthorized or this is a unit-test host.
    ///
    /// The test-host guard mirrors the ones on Accessibility and Notifications
    /// in ``RuntimeEnvironment``: `xcodebuild test` re-signs the app on every
    /// run, so a capture attempt would re-prompt the developer for camera
    /// access each time — and would turn their camera on to do it.
    func start() {
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        guard authorization.permitsCapture else { return }
        engine.start()
    }

    /// Closes the camera and forgets the last verdict.
    func stop() {
        engine.stop()
    }

    /// Prompts for camera access when the status is undecided, then reports
    /// the outcome on the main actor.
    func requestAuthorization(
        completion: @escaping @MainActor (CameraAuthorization) -> Void
    ) {
        let current = authorization
        guard !RuntimeEnvironment.isUnitTestHost, current.canPrompt else {
            Task { @MainActor in completion(current) }
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in
                completion(VisionCameraPresenceSensor.currentAuthorization)
            }
        }
    }

    /// Translates `AVAuthorizationStatus` into the domain enum. `@unknown`
    /// futures resolve to ``CameraAuthorization/denied`` — the safe direction,
    /// because an unrecognised status must never be read as consent.
    static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
}

/// The capture-and-detect engine: everything that touches the camera.
///
/// ### What this class does and does not do
///
/// It opens the default video device, pulls frames onto a private serial
/// queue, and — at most once every
/// ``PresenceDetectionPolicy/analysisIntervalSeconds`` — hands one frame's
/// pixel buffer to `VNDetectHumanRectanglesRequest`. The request returns
/// bounding boxes with confidences. The class keeps one `Bool` and a
/// timestamp from that and drops everything else on the floor.
///
/// It never copies a pixel buffer, never encodes an image, never writes a
/// file, and never opens a socket. There is no code path here that could
/// persist or transmit a frame, and the imports that would make one possible
/// (`ImageIO`, `CoreImage`, `UniformTypeIdentifiers`, `URLSession`) are absent
/// by design. Frames arriving between analyses are not read at all — the
/// delegate returns before touching the buffer.
///
/// `VNDetectHumanRectanglesRequest` is a *detector*, not a recogniser. It
/// answers "is there a human shape here"; it does not compute a face
/// embedding, does not build a template, and has nothing to match against.
/// Curfew never calls Vision's face-landmark or feature-print APIs.
///
/// `nonisolated` and `@unchecked Sendable`: the capture delegate is invoked on
/// ``queue``, not the main actor, and every piece of shared state below is
/// guarded by ``lock``.
final nonisolated class CameraPresenceEngine: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Minimum Vision confidence for a detection to count as a person.
    ///
    /// Set high enough that a coat over a chair or a poster does not read as a
    /// body. A false "present" is the more expensive error here: it would keep
    /// Curfew reporting a user who has gone home, and it would let a
    /// distraction nudge fire into an empty room.
    private static let minimumConfidence: Float = 0.5

    /// Serial queue owning the session and running Vision. One queue for both
    /// means session mutation and frame delivery cannot race each other.
    private let queue = DispatchQueue(
        label: "studio.hypertext.curfew.presence-camera",
        qos: .utility
    )

    /// Guards every stored property below, all of which are written from
    /// ``queue`` and read from the main actor.
    private let lock = NSLock()

    private var storedObservation: PersonObservation = .never
    private var running = false
    private var lastAnalysis: Date = .distantPast

    /// Live capture session. `nil` whenever stopped — the graph is torn down
    /// rather than paused, so the device is released and the camera indicator
    /// light goes out. Touched only on ``queue``.
    private var session: AVCaptureSession?

    /// Reusable detector, built on first frame rather than at construction so
    /// an engine that never runs — which is every engine on a default install
    /// — never touches Vision at all. Touched only on ``queue``, so the lazy
    /// initialisation cannot race.
    private lazy var request: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        // A desk webcam sees head and shoulders, not legs. Upper-body mode is
        // both more accurate for that framing and cheaper to run.
        request.upperBodyOnly = true
        return request
    }()

    /// Whether capture is running.
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// The most recent verdict.
    var latestObservation: PersonObservation {
        lock.lock()
        defer { lock.unlock() }
        return storedObservation
    }

    /// Opens the camera. Idempotent.
    ///
    /// `running` flips synchronously so a caller polling ``isRunning`` on the
    /// next tick sees the intent immediately; if the device then fails to
    /// open, ``openSession()`` flips it back and the monitor records a stop.
    func start() {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()
        queue.async { [weak self] in self?.openSession() }
    }

    /// Closes the camera and forgets the last verdict. Idempotent.
    ///
    /// Clearing the observation is not housekeeping, it is the point: a
    /// consumer that kept reading ``latestObservation`` after a stop would be
    /// answering "is someone there?" from a frame taken before the camera was
    /// switched off.
    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        storedObservation = .never
        lastAnalysis = .distantPast
        lock.unlock()
        guard wasRunning else { return }
        queue.async { [weak self] in self?.closeSession() }
    }

    // MARK: - Session lifecycle (queue)

    private func openSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            presenceLogger.error("no video capture device available")
            markStopped()
            return
        }

        let session = AVCaptureSession()
        // The lowest preset that still detects an upper body reliably. Fewer
        // pixels means less image data existing even transiently in memory,
        // and materially less power on a signal sampled twice a minute.
        session.sessionPreset = .medium

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                presenceLogger.error("capture session refused the camera input")
                markStopped()
                return
            }
            session.addInput(input)
        } catch {
            let description = String(describing: error)
            presenceLogger.error("camera input unavailable: \(description, privacy: .public)")
            markStopped()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            presenceLogger.error("capture session refused the video output")
            markStopped()
            return
        }
        session.addOutput(output)

        // A `stop()` can land between the async hop and here. Bail rather than
        // start a session nobody asked for any more.
        guard isRunning else { return }
        self.session = session
        session.startRunning()
    }

    private func closeSession() {
        guard let session else { return }
        session.stopRunning()
        // Tearing the graph down rather than just stopping it is what
        // guarantees the device is released and the indicator light goes out.
        for output in session.outputs {
            session.removeOutput(output)
        }
        for input in session.inputs {
            session.removeInput(input)
        }
        self.session = nil
    }

    private func markStopped() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private func record(_ signal: PersonSignal, at moment: Date) {
        lock.lock()
        // A frame that lands after `stop()` must not resurrect the session's
        // verdict — the delegate can be mid-flight when the user flips the
        // switch off.
        if running {
            storedObservation = PersonObservation(signal: signal, timestamp: moment)
        }
        lock.unlock()
    }

    // MARK: - Frame delivery (queue)

    /// Handles one delivered frame.
    ///
    /// Everything that touches a pixel buffer is in this one method, and it is
    /// deliberately short: throttle, detect, keep a `Bool`, return.
    ///
    /// The throttle check comes before any access to the sample buffer, so a
    /// frame arriving inside the analysis interval is discarded without its
    /// pixels ever being read. At the configured cadence that is the
    /// overwhelming majority of frames.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        lock.lock()
        let due = now.timeIntervalSince(lastAnalysis)
            >= PresenceDetectionPolicy.analysisIntervalSeconds
        let live = running
        if due, live {
            lastAnalysis = now
        }
        lock.unlock()
        guard due, live else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // A failed analysis is not evidence of an empty chair. Leaving the
            // previous observation in place lets it age out to `.unavailable`
            // through the monitor's staleness tolerance, which is the honest
            // outcome for "the camera stopped answering".
            let description = String(describing: error)
            presenceLogger.error("vision request failed: \(description, privacy: .public)")
            return
        }

        let observations = request.results ?? []
        let sawPerson = observations.contains { $0.confidence >= Self.minimumConfidence }
        // The count, the boxes, and the confidences end here. Only the Bool
        // survives this line.
        record(sawPerson ? .detected : .notDetected, at: now)
    }
}
