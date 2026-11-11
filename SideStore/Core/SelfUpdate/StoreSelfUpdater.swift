//
//  StoreSelfUpdater.swift
//  Silo Store
//

import CoreData
import UIKit

/// Keeps Silo Store itself up to date.
///
/// The update check is the normal source fetch (on launch and in the background) and
/// needs no VPN. When it finds a newer version the app asks first. On "Update now" it
/// switches LocalDevVPN on, installs, and switches LocalDevVPN off again.
final class StoreSelfUpdater
{
    static let shared = StoreSelfUpdater()
    static let didChangeNotification = Notification.Name("StoreSelfUpdaterDidChange")

    enum State: Equatable
    {
        case upToDate
        case updateAvailable(version: String)
        case connecting(version: String)
        case installing(version: String)
        case failed(message: String)
    }

    private static let askBeforeUpdatingKey = "siloAutoInstallStoreUpdates"
    private static let vpnEnabledByUpdaterKey = "siloVPNEnabledByUpdater"

    /// The scheme LocalDevVPN opens to bring us back after it switches the VPN.
    private static let callbackScheme = "silostore"
    private static let vpnReadyTimeout = 30
    private static let vpnOffDelayAfterLaunch: TimeInterval = 8

    private(set) var state: State = .upToDate
    private var isBusy = false
    private var waitingForVPN = false
    private var lastPromptedVersion: String?
    private var becomeActiveObserver: NSObjectProtocol?

    private init()
    {
        self.becomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appDidBecomeActive()
        }
    }

    /// Whether the app asks before updating. Defaults to on.
    var askBeforeUpdating: Bool {
        return UserDefaults.standard.object(forKey: Self.askBeforeUpdatingKey) as? Bool ?? true
    }

    private var vpnEnabledByUpdater: Bool {
        get { UserDefaults.standard.bool(forKey: Self.vpnEnabledByUpdaterKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.vpnEnabledByUpdaterKey) }
    }

    var statusText: String {
        switch self.state
        {
        case .upToDate:
            return NSLocalizedString("Up to date", comment: "")
        case .updateAvailable(let version):
            return String(format: NSLocalizedString("Update %@ is ready. Tap to install", comment: ""), version)
        case .connecting(let version):
            return String(format: NSLocalizedString("Turning on LocalDevVPN for %@…", comment: ""), version)
        case .installing(let version):
            return String(format: NSLocalizedString("Installing update %@…", comment: ""), version)
        case .failed(let message):
            return String(format: NSLocalizedString("Update failed: %@. Tap to retry", comment: ""), message)
        }
    }

    // MARK: Checking

    /// Call after the sources have been fetched.
    func sourcesDidUpdate()
    {
        DispatchQueue.main.async {
            self.refreshState()

            guard case .updateAvailable(let version) = self.state, self.askBeforeUpdating else { return }

            // Give the launch screen time to finish so the alert has a stable screen to sit on.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.promptForUpdate(version: version)
            }
        }
    }

    /// Call once the app has finished launching.
    func appDidLaunch()
    {
        // The VPN was switched on for an update that has since restarted the app.
        guard self.vpnEnabledByUpdater, !self.isBusy else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.vpnOffDelayAfterLaunch) {
            self.switchVPNOffIfEnabledByUpdater()
        }
    }

    func refreshState()
    {
        guard !self.isBusy else { return }

        let context = DatabaseManager.shared.viewContext

        if let installedApp = InstalledApp.fetchAltStore(in: context),
           installedApp.hasUpdate,
           let version = installedApp.storeApp?.latestSupportedVersion?.version
        {
            self.setState(.updateAvailable(version: version))
        }
        else
        {
            self.setState(.upToDate)
        }
    }

    // MARK: Asking

    private func promptForUpdate(version: String)
    {
        guard self.lastPromptedVersion != version,
              UIApplication.shared.applicationState == .active,
              let presenter = self.topViewController() else { return }

        self.lastPromptedVersion = version

        let alert = UIAlertController(
            title: NSLocalizedString("Update Silo Store", comment: ""),
            message: String(format: NSLocalizedString("Version %@ is ready. Silo Store will turn LocalDevVPN on for the update and off again afterwards.", comment: ""), version),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Later", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Update now", comment: ""), style: .default) { _ in
            self.beginUpdate()
        })
        presenter.present(alert, animated: true)
    }

    // MARK: Updating

    /// The user tapped the update status: retry a failed update, or start a waiting one.
    func userRequestedUpdate()
    {
        if case .failed = self.state
        {
            self.refreshState()
        }
        
        self.beginUpdate()
    }
    
    /// Starts the update: straight away if the VPN is already up, otherwise via LocalDevVPN.
    func beginUpdate()
    {
        guard !self.isBusy else { return }
        guard case .updateAvailable(let version) = self.state else { return }

        self.isBusy = true

        Task {
            let result = await isMinimuxerReady()

            DispatchQueue.main.async {
                if case .success(let ready) = result, ready
                {
                    self.installNow(version: version)
                }
                else
                {
                    self.switchVPNOn(version: version)
                }
            }
        }
    }

    private func switchVPNOn(version: String)
    {
        self.setState(.connecting(version: version))
        self.vpnEnabledByUpdater = true
        self.waitingForVPN = true

        self.openLocalDevVPN(action: "enable") { success in
            guard !success else { return }
            self.waitingForVPN = false
            self.vpnEnabledByUpdater = false
            self.finish(failure: NSLocalizedString("LocalDevVPN could not be opened", comment: ""))
        }
    }

    /// LocalDevVPN has opened us again; wait for the tunnel to come up, then install.
    private func appDidBecomeActive()
    {
        guard self.waitingForVPN, case .connecting(let version) = self.state else { return }
        self.waitingForVPN = false

        Task {
            for _ in 0 ..< Self.vpnReadyTimeout
            {
                if case .success(let ready) = await isMinimuxerReady(), ready
                {
                    DispatchQueue.main.async { self.installNow(version: version) }
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            DispatchQueue.main.async {
                self.finish(failure: NSLocalizedString("LocalDevVPN did not connect", comment: ""))
                self.switchVPNOffIfEnabledByUpdater()
            }
        }
    }

    private func installNow(version: String)
    {
        let context = DatabaseManager.shared.viewContext

        guard let installedApp = InstalledApp.fetchAltStore(in: context), installedApp.hasUpdate else {
            self.isBusy = false
            self.refreshState()
            self.switchVPNOffIfEnabledByUpdater()
            return
        }

        self.setState(.installing(version: version))

        AppManager.shared.update(installedApp, presentingViewController: self.topViewController()) { result in
            DispatchQueue.main.async {
                switch result
                {
                case .success:
                    self.isBusy = false
                    self.refreshState()
                case .failure(let error):
                    self.finish(failure: error.localizedDescription)
                }

                self.switchVPNOffIfEnabledByUpdater()
            }
        }
    }

    private func finish(failure message: String)
    {
        self.isBusy = false
        self.setState(.failed(message: message))
    }

    // MARK: LocalDevVPN

    private func switchVPNOffIfEnabledByUpdater()
    {
        guard self.vpnEnabledByUpdater else { return }
        self.vpnEnabledByUpdater = false
        self.openLocalDevVPN(action: "disable", completion: nil)
    }

    private func openLocalDevVPN(action: String, completion: ((Bool) -> Void)?)
    {
        guard let url = URL(string: "localdevvpn://\(action)?scheme=\(Self.callbackScheme)") else {
            completion?(false)
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            DispatchQueue.main.async { completion?(success) }
        }
    }

    // MARK: Helpers

    private func topViewController() -> UIViewController?
    {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first

        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController
        {
            top = presented
        }
        return top
    }

    private func setState(_ state: State)
    {
        guard self.state != state else { return }
        self.state = state
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
