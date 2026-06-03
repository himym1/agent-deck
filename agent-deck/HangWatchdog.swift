import Foundation
import QuartzCore
import os

/// Crash-proof main-thread hang detector + auto-profiler.
///
/// A background thread watches a main-thread heartbeat. When the main thread
/// stops beating for longer than `threshold` (i.e. it's hung mid-frame during a
/// janky scroll), the watchdog spawns the OS `/usr/bin/sample` tool **on this
/// process from the outside** and dumps the hung main thread's exact backtrace
/// to a file. Nothing in-process is suspended, walked, or signalled — so unlike
/// a hand-rolled stack sampler this cannot crash the app. The captured file
/// names the precise calculation that hung the frame.
///
/// On by default; disable with
///   `defaults write streetcoding.agent-deck HangWatchdogEnabled -bool NO`
/// Read the watchdog log live with:
///   log stream --predicate 'subsystem == "streetcoding.agent-deck" AND category == "HangWatchdog"' --info
/// Hang backtraces are written to `/tmp/agentdeck-hang-<n>.txt`.
nonisolated final class HangWatchdog: @unchecked Sendable {
    static let shared = HangWatchdog()
    static let logger = Logger(subsystem: "streetcoding.agent-deck", category: "HangWatchdog")

    private let lock = NSLock()
    private var lastBeat: CFTimeInterval = 0
    private var mainTimer: Timer?
    private var bgTimer: DispatchSourceTimer?
    private var sampling = false
    private var sampleIndex = 0
    private var hangActive = false
    private var hangStartBeat: CFTimeInterval = 0

    // MARK: Hitch capture (scroll jank that never reaches the hang threshold)
    private var hitchSampling = false
    private var hitchIndex = 0
    private var lastHitchCapture: CFTimeInterval = 0
    /// Throttle: at most one hitch backtrace this often, so a sustained-jank
    /// scroll produces a handful of captures, not hundreds.
    private let hitchThrottle: CFTimeInterval = 3
    /// `sample` only accepts whole seconds; 1s during a stuttering scroll still
    /// lands dozens of samples on the hot stack.
    private let hitchSampleSeconds = 1

    /// A frame longer than this (ms) counts as a hang worth capturing. 60fps is
    /// 16.7ms; 150ms is ~9 dropped frames — a clear stall, not normal churn.
    /// Override with `defaults write streetcoding.agent-deck HangWatchdogThresholdMs -int 50`
    /// to also catch sustained mid-jank (steady 30fps reads as ~33ms frames).
    private var threshold: CFTimeInterval = 0.15
    /// How long `sample` profiles once a hang is detected.
    private let sampleSeconds = 2

    func start() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "HangWatchdogEnabled") != nil,
           defaults.bool(forKey: "HangWatchdogEnabled") == false {
            return
        }
        if let override = defaults.object(forKey: "HangWatchdogThresholdMs") as? NSNumber,
           override.doubleValue >= 16 {
            threshold = override.doubleValue / 1000
        }
        lastBeat = CACurrentMediaTime()

        // Heartbeat on the main runloop — stops the instant the main thread hangs.
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.lastBeat = CACurrentMediaTime()
            if self.hangActive {
                let hung = (self.lastBeat - self.hangStartBeat) * 1000
                self.hangActive = false
                self.lock.unlock()
                Self.logger.error("HANG ENDED — main thread was blocked ~\(Int(hung))ms")
            } else {
                self.lock.unlock()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        mainTimer = t

        // Background watcher.
        let q = DispatchQueue(label: "streetcoding.agent-deck.hangwatchdog", qos: .userInitiated)
        let bg = DispatchSource.makeTimerSource(queue: q)
        bg.schedule(deadline: .now() + 0.1, repeating: 0.04)
        bg.setEventHandler { [weak self] in self?.check() }
        bg.resume()
        bgTimer = bg

        Self.logger.info("HangWatchdog started (threshold \(Int(self.threshold * 1000))ms)")
    }

    private func check() {
        let now = CACurrentMediaTime()
        lock.lock()
        let gap = now - lastBeat
        if gap <= threshold { lock.unlock(); return }
        if !hangActive { hangActive = true; hangStartBeat = lastBeat }
        if sampling { lock.unlock(); return }   // already capturing this stall
        sampling = true
        sampleIndex += 1
        let index = sampleIndex
        lock.unlock()
        captureSample(index: index, blockedMs: Int(gap * 1000))
    }

    private func captureSample(index: Int, blockedMs: Int) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = "/tmp/agentdeck-hang-\(index).txt"
        Self.logger.error("HANG detected (~\(blockedMs)ms blocked) — capturing main-thread backtrace → \(path, privacy: .public)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        proc.arguments = ["\(pid)", "\(sampleSeconds)", "-file", path, "-mayDie"]
        proc.standardOutput = nil
        proc.standardError = nil
        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.sampling = false; self.lock.unlock()
            Self.logger.error("HANG sample #\(index) ready → \(path, privacy: .public)")
        }
        do {
            try proc.run()
        } catch {
            lock.lock(); sampling = false; lock.unlock()
            Self.logger.error("HANG sample spawn failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Capture a short, throttled backtrace for a *hitch* — a dropped scroll
    /// frame that's too brief to trip the hang threshold but is exactly the
    /// sustained "feels slow" jank we're hunting. Called from the scroll
    /// profiler when a frame gap exceeds its backtrace threshold. Crash-proof
    /// for the same reason as the hang path: it shells out to `/usr/bin/sample`
    /// rather than walking the stack in-process. Writes `/tmp/agentdeck-hitch-<n>.txt`.
    func captureHitch(gapMs: Int) {
        let now = CACurrentMediaTime()
        lock.lock()
        if hitchSampling || now - lastHitchCapture < hitchThrottle { lock.unlock(); return }
        hitchSampling = true
        lastHitchCapture = now
        hitchIndex += 1
        let index = hitchIndex
        lock.unlock()

        let pid = ProcessInfo.processInfo.processIdentifier
        let path = "/tmp/agentdeck-hitch-\(index).txt"
        Self.logger.error("HITCH (~\(gapMs)ms dropped frame) — sampling hot stack → \(path, privacy: .public)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        // Fine sampling interval (1ms) so a 1s window over a stuttering scroll
        // still resolves the dominant frame-blocking call.
        proc.arguments = ["\(pid)", "\(hitchSampleSeconds)", "1", "-file", path, "-mayDie"]
        proc.standardOutput = nil
        proc.standardError = nil
        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.hitchSampling = false; self.lock.unlock()
            Self.logger.error("HITCH sample #\(index) ready → \(path, privacy: .public)")
        }
        do {
            try proc.run()
        } catch {
            lock.lock(); hitchSampling = false; lock.unlock()
            Self.logger.error("HITCH sample spawn failed: \(String(describing: error), privacy: .public)")
        }
    }
}
