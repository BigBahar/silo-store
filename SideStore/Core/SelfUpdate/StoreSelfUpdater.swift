//
//  StoreSelfUpdater.swift
//  Silo Store
//

import CoreData
import UIKit

/// Keeps Silo Store itself up to date.
///
/// The update check is the normal source fetch (on launch and in the background);
/// this reports what that check found and installs the update without being asked.
final class StoreSelfUpdater
{
    static let shared = StoreSelfUpdater()
    static let didChangeNotification = Notification.Name("StoreSelfUpdaterDidChange")

    enum State: Equatable
    {
        case upToDate
        case updateAvailable(version: String)
        case installing(version: String)
        case failed(message: String)
    }

    private static let autoInstallKey = "siloAutoInstallStoreUpdates"

    private(set) var state: State = .upToDate
    private var isInstalling = false
    private var lastAttemptedVersion: String?

    private init() {}

    var autoInstallEnabled: Bool {
        return UserDefaults.standard.object(forKey: Self.autoInstallKey) as? Bool ?? true
    }

    var statusText: String {
        switch self.state
        {
        case .upToDate:
            return NSLocalizedString("Up to date", comment: "")
        case .updateAvailable(let version):
            return String(format: NSLocalizedString("Update %@ is ready. Tap to install", comment: ""), version)
        case .installing(let version):
            return String(format: NSLocalizedString("Installing update %@…", comment: ""), version)
        case .failed(let message):
            return String(format: NSLocalizedString("Update failed: %@. Tap to retry", comment: ""), message)
        }
    }

    /// Call after the sources have been fetched.
    func sourcesDidUpdate()
    {
        DispatchQueue.main.async {
            self.refreshState()

            if self.autoInstallEnabled
            {
                self.installUpdateIfAvailable(userInitiated: false)
            }
        }
    }

    func refreshState()
    {
        guard !self.isInstalling else { return }

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

    func installUpdateIfAvailable(userInitiated: Bool)
    {
        guard !self.isInstalling else { return }

        let context = DatabaseManager.shared.viewContext

        guard let installedApp = InstalledApp.fetchAltStore(in: context),
              installedApp.hasUpdate,
              let version = installedApp.storeApp?.latestSupportedVersion?.version else { return }

        // An automatic attempt is made once per version per launch, so a failing install doesn't loop.
        guard userInitiated || self.lastAttemptedVersion != version else { return }
        self.lastAttemptedVersion = version

        self.isInstalling = true
        self.setState(.installing(version: version))

        AppManager.shared.update(installedApp, presentingViewController: nil) { result in
            DispatchQueue.main.async {
                self.isInstalling = false

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
