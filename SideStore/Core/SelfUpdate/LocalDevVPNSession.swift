//
//  LocalDevVPNSession.swift
//  Silo Store
//

import UIKit

/// Switches the tunnel (LocalDevVPN, or Tailscale through Shortcuts) on for the length of an
/// install, update or refresh, and off again.
///
/// Every app operation goes through `PipelineRunner.perform`, which takes a session
/// before it starts and gives it back when it ends. If the tunnel is already up (the
/// user's own automation, or LocalDevVPN left on) nothing is switched. The switching only
/// happens while the app is on screen, because only then can it open LocalDevVPN; a
/// background refresh is left to whatever starts it.
actor LocalDevVPNSession
{
    static let shared = LocalDevVPNSession()

    private static let enabledKey = "siloVPNEnabledByUpdater"

    /// The scheme LocalDevVPN opens to bring us back after it switches the VPN.
    private static let callbackScheme = "silostore"
    private static let readyTimeout = 30
    private static let returnTimeout = 20
    private static let offDelayAfterLaunch: TimeInterval = 8

    private var activeCount = 0
    private var isEnabling = false

    /// Remembered across launches: installing a new Silo Store restarts the app before it can switch the VPN off.
    private var enabledByUs: Bool {
        get { return UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    // MARK: Session

    /// Call before an operation. Returns once the tunnel is up, or when it could not be brought up.
    func acquire() async
    {
        self.activeCount += 1
        await self.ensureConnected()
    }

    /// Call when the operation ends, however it ends.
    func release() async
    {
        self.activeCount = max(0, self.activeCount - 1)
        await self.switchOffIfNeeded()
    }

    /// Call once at launch: finishes a switch-off that an app restart interrupted.
    nonisolated func appDidLaunch()
    {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.offDelayAfterLaunch * 1_000_000_000))
            await self.switchOffIfNeeded()
        }
    }

    // MARK: Switching

    private func ensureConnected() async
    {
        if await Self.isReady() { return }

        if self.isEnabling
        {
            await self.waitUntilReady()
            return
        }

        guard await Self.isAppActive() else { return }

        self.isEnabling = true
        defer { self.isEnabling = false }

        self.enabledByUs = true

        guard await Self.open(action: "enable") else {
            self.enabledByUs = false
            return
        }

        await Self.waitForReturn()
        await self.waitUntilReady()
    }

    private func waitUntilReady() async
    {
        for _ in 0 ..< Self.readyTimeout * 2
        {
            if await Self.isReady() { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func switchOffIfNeeded() async
    {
        guard self.activeCount == 0, self.enabledByUs else { return }

        // If the app is not on screen the link cannot open; the flag stays and the next launch tries again.
        if await Self.open(action: "disable")
        {
            self.enabledByUs = false
        }
    }

    // MARK: Helpers

    private static func isReady() async -> Bool
    {
        if case .success(let ready) = await isMinimuxerReady()
        {
            return ready
        }
        return false
    }

    @MainActor
    private static func isAppActive() -> Bool
    {
        return UIApplication.shared.applicationState == .active
    }

    @MainActor
    private static func open(action: String) async -> Bool
    {
        let url: URL?
        switch SiloTunnel.mode
        {
        case .localDevVPN:
            url = URL(string: "localdevvpn://\(action)?scheme=\(callbackScheme)")
        case .tailscale:
            url = SiloTunnel.shortcutURL(name: action == "enable" ? SiloTunnel.onShortcutName : SiloTunnel.offShortcutName)
        }
        
        guard let url else { return false }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Waits for the app to leave the foreground for LocalDevVPN and come back.
    private static func waitForReturn() async
    {
        var left = false

        for tick in 0 ..< returnTimeout * 4
        {
            let active = await isAppActive()

            if !active
            {
                left = true
            }
            else if left
            {
                return
            }
            else if tick > 12
            {
                // Never left: LocalDevVPN did not open.
                return
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
