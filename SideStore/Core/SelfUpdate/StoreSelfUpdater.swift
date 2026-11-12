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
/// installs like any other app; the LocalDevVPN switching is done by LocalDevVPNSession.
final class StoreSelfUpdater
{
    static let shared = StoreSelfUpdater()
    static let didChangeNotification = Notification.Name("StoreSelfUpdaterDidChange")

    enum State: Equatable
    {
        case upToDate
        case checking
        case updateAvailable(version: String)
        case connecting(version: String)
        case installing(version: String)
        case failed(message: String)
    }

    private static let askBeforeUpdatingKey = "siloAutoInstallStoreUpdates"

    private(set) var state: State = .upToDate
    private var isBusy = false
    private var lastPromptedVersion: String?

    private init() {}

    /// Whether the app asks before updating. Defaults to on.
    var askBeforeUpdating: Bool {
        return UserDefaults.standard.object(forKey: Self.askBeforeUpdatingKey) as? Bool ?? true
    }

    var statusText: String {
        switch self.state
        {
        case .upToDate:
            return NSLocalizedString("Up to date. Tap to check", comment: "")
        case .checking:
            return NSLocalizedString("Checking for updates…", comment: "")
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

    /// Checks the feed now, for the Check for Updates row. Prompts if a newer version is found.
    func checkNow(completion: @escaping (State) -> Void)
    {
        guard !self.isBusy else {
            completion(self.state)
            return
        }

        self.isBusy = true
        self.setState(.checking)

        AppManager.shared.updateAllSources { result in
            DispatchQueue.main.async {
                self.isBusy = false

                switch result
                {
                case .failure(let error):
                    self.setState(.failed(message: error.localizedDescription))
                case .success:
                    self.refreshState()

                    if case .updateAvailable(let version) = self.state
                    {
                        self.lastPromptedVersion = nil
                        self.promptForUpdate(version: version)
                    }
                }

                completion(self.state)
            }
        }
    }

    /// Call once the app has finished launching.
    func appDidLaunch()
    {
        LocalDevVPNSession.shared.appDidLaunch()
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
              let presenter = UIViewController.siloTopMost() else { return }

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

    func beginUpdate()
    {
        guard !self.isBusy else { return }
        guard case .updateAvailable(let version) = self.state else { return }

        let context = DatabaseManager.shared.viewContext

        guard let installedApp = InstalledApp.fetchAltStore(in: context), installedApp.hasUpdate else {
            self.refreshState()
            return
        }

        self.isBusy = true
        self.setState(.installing(version: version))

        AppManager.shared.update(installedApp, presentingViewController: UIViewController.siloTopMost()) { result in
            DispatchQueue.main.async {
                self.isBusy = false

                switch result
                {
                case .success:
                    self.refreshState()
                case .failure(let error):
                    self.setState(.failed(message: error.localizedDescription))
                }
            }
        }
    }

    private func setState(_ state: State)
    {
        guard self.state != state else { return }
        self.state = state
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
