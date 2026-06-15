import Foundation
import os

/// Owns the single shared `PiAutoInstaller` and drives the launch-time silent
/// update of the Pi CLI. The Doctor's manual install/update controls use the
/// same `installer` instance, so the two paths share one `isRunning` guard and
/// one `phase`: a launch-triggered update in flight shows up in the Doctor, and
/// a manual update can't race the launch one.
///
/// When the user has opted in via the Doctor toggle, `runIfEnabled()` checks the
/// installed Pi against the latest release once per launch and, if a newer
/// version exists, runs the same method-aware update the "Update Pi" button
/// uses. The enabled flag is read straight from `AppSettingsStore.shared` so
/// this stays decoupled from `AppViewModel` and can run from
/// `applicationDidFinishLaunching` alongside the Sparkle app-update check.
@MainActor
final class PiAgentAutoUpdater {
    static let shared = PiAgentAutoUpdater()

    /// The one installer both the launch path and the Doctor act through.
    let installer = PiAutoInstaller()

    private let updateService = PiAgentUpdateService()
    private let log = Logger(subsystem: "streetcoding.agent-deck", category: "PiAutoUpdate")

    /// Guards against running more than once per launch.
    private var didRunThisLaunch = false

    private init() {}

    /// Runs the check+update if the user enabled it. Safe to call repeatedly;
    /// only the first call per launch does work. Returns silently when disabled,
    /// already run, when Pi is missing, when already up to date, or when a manual
    /// install/update is already running.
    func runIfEnabled() async {
        guard !didRunThisLaunch else { return }
        guard AppSettingsStore.shared.settings.piAgentAutoUpdateEnabled else { return }
        guard !installer.isRunning else { return }
        didRunThisLaunch = true

        let status = await updateService.loadStatus()
        guard status.isInstalled, let current = status.currentVersion else {
            // Nothing to update — install is the Doctor's job, not auto-update's.
            return
        }
        guard case let .updateAvailable(latest) = status.updateState else {
            log.info("Pi auto-update: already up to date (\(current, privacy: .public)).")
            return
        }

        log.info("Pi auto-update: \(current, privacy: .public) -> \(latest, privacy: .public), updating…")
        if await installer.update() {
            let newVersion = await updateService.loadCurrentVersion() ?? latest
            log.info("Pi auto-update: updated to \(newVersion, privacy: .public).")
        } else {
            // The failure (with retry + Terminal fallback) stays on `installer.phase`
            // so the Doctor surfaces it the next time it's opened.
            log.error("Pi auto-update failed; see Doctor for detail.")
        }
    }
}
