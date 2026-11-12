//
//  MyAppsComponents.swift
//  AltStore
//
//  Created by Riley Testut on 7/17/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

final class InstalledAppCollectionViewCell: UICollectionViewCell
{
    var bundleIdentifier: String?
    private(set) var deactivateBadge: UIView?
    
    @IBOutlet var bannerView: AppBannerView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        
        let deactivateBadge = UIView()
        deactivateBadge.translatesAutoresizingMaskIntoConstraints = false
        deactivateBadge.isHidden = true
        self.addSubview(deactivateBadge)
        
        // Solid background to make the X opaque white.
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .white
        deactivateBadge.addSubview(backgroundView)
                    
        let badgeView = UIImageView(image: UIImage(systemName: "xmark.circle.fill"))
        badgeView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
        badgeView.tintColor = .systemRed
        deactivateBadge.addSubview(badgeView, pinningEdgesWith: .zero)
        
        NSLayoutConstraint.activate([
            deactivateBadge.centerXAnchor.constraint(equalTo: self.bannerView.iconImageView.trailingAnchor),
            deactivateBadge.centerYAnchor.constraint(equalTo: self.bannerView.iconImageView.topAnchor),
            
            backgroundView.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            backgroundView.widthAnchor.constraint(equalTo: badgeView.widthAnchor, multiplier: 0.5),
            backgroundView.heightAnchor.constraint(equalTo: badgeView.heightAnchor, multiplier: 0.5)
        ])
        
        self.deactivateBadge = deactivateBadge
        
        self.installExpiryBar()
    }
    
    // MARK: Expiry bar
    
    private let expiryTrack = UIView()
    private let expiryFill = UIView()
    private var expiryFillWidth: NSLayoutConstraint?
    
    private func installExpiryBar()
    {
        self.expiryTrack.translatesAutoresizingMaskIntoConstraints = false
        self.expiryTrack.layer.cornerRadius = 1.5
        self.expiryTrack.clipsToBounds = true
        self.expiryTrack.isUserInteractionEnabled = false
        self.expiryTrack.isHidden = true
        self.expiryTrack.isAccessibilityElement = false
        
        self.expiryFill.translatesAutoresizingMaskIntoConstraints = false
        self.expiryFill.isAccessibilityElement = false
        self.expiryTrack.addSubview(self.expiryFill)
        self.bannerView.addSubview(self.expiryTrack)
        
        NSLayoutConstraint.activate([
            self.expiryTrack.leadingAnchor.constraint(equalTo: self.bannerView.leadingAnchor, constant: SiloSpace.s4),
            self.expiryTrack.trailingAnchor.constraint(equalTo: self.bannerView.trailingAnchor, constant: -SiloSpace.s4),
            self.expiryTrack.bottomAnchor.constraint(equalTo: self.bannerView.bottomAnchor, constant: -SiloSpace.s2),
            self.expiryTrack.heightAnchor.constraint(equalToConstant: 3),
            
            self.expiryFill.leadingAnchor.constraint(equalTo: self.expiryTrack.leadingAnchor),
            self.expiryFill.topAnchor.constraint(equalTo: self.expiryTrack.topAnchor),
            self.expiryFill.bottomAnchor.constraint(equalTo: self.expiryTrack.bottomAnchor)
        ])
    }
    
    /// Shows how much of the 7-day profile is left: cyan, amber under two days, red when expired.
    func setExpiry(remaining: TimeInterval)
    {
        let week: TimeInterval = 7 * 24 * 60 * 60
        let raw = remaining / week
        let fraction = raw.isFinite ? min(max(raw, 0.02), 1) : 1
        
        self.expiryFillWidth?.isActive = false
        let width = self.expiryFill.widthAnchor.constraint(equalTo: self.expiryTrack.widthAnchor, multiplier: fraction)
        width.isActive = true
        self.expiryFillWidth = width
        
        self.expiryTrack.backgroundColor = SiloColor.raisedStrong
        
        if remaining <= 0
        {
            self.expiryFill.backgroundColor = SiloColor.danger
        }
        else if remaining < 2 * 24 * 60 * 60
        {
            self.expiryFill.backgroundColor = SiloColor.warn
        }
        else
        {
            self.expiryFill.backgroundColor = SiloColor.accent
        }
        
        self.expiryTrack.isHidden = false
    }
    
    func hideExpiry()
    {
        self.expiryTrack.isHidden = true
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.bannerView?.button?.resetDisplayState()
    }
}

final class InstalledAppsCollectionFooterView: UICollectionReusableView
{
    @IBOutlet var textLabel: UILabel!
    @IBOutlet var button: UIButton!
}

final class NoUpdatesCollectionViewCell: UICollectionViewCell
{
    @IBOutlet var blurView: UIVisualEffectView!
    @IBOutlet var textLabel: UILabel!
    @IBOutlet var button: UIButton!
    
    /// The status headline ("All apps fresh"), what comes next, and the one primary action.
    let headlineLabel = UILabel()
    let detailLabel = UILabel()
    let refreshButton = UIButton(type: .system)
    
    fileprivate var isRefreshing = false
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.contentView.preservesSuperviewLayoutMargins = true
        
        // The old "No Updates Available" pill is replaced by the status block below.
        self.blurView.isHidden = true
        self.installStatusBlock()
        
        let font = self.textLabel.font ?? UIFont.systemFont(ofSize: 17)
        let configuration = UIImage.SymbolConfiguration(font: font)
        let image = UIImage(systemName: "ellipsis.circle", withConfiguration: configuration)
        
        self.button.setTitle("", for: .normal)
        self.button.setImage(image, for: .normal)
    }
}

private extension NoUpdatesCollectionViewCell
{
    func installStatusBlock()
    {
        self.headlineLabel.font = SiloFont.uiFont(size: 32, weight: 800, style: .largeTitle)
        self.headlineLabel.adjustsFontForContentSizeCategory = true
        self.headlineLabel.numberOfLines = 0
        self.headlineLabel.accessibilityTraits = .header
        
        self.detailLabel.font = SiloFont.uiFont(.body)
        self.detailLabel.adjustsFontForContentSizeCategory = true
        self.detailLabel.numberOfLines = 0
        
        let stack = UIStackView(arrangedSubviews: [self.headlineLabel, self.detailLabel, self.refreshButton])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = SiloSpace.s1
        stack.setCustomSpacing(SiloSpace.s4, after: self.detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: self.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: SiloSpace.s2),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: self.contentView.bottomAnchor, constant: -SiloSpace.s2)
        ])
        
        self.applyLook()
    }
}

extension NoUpdatesCollectionViewCell
{
    func setRefreshing(_ refreshing: Bool)
    {
        self.isRefreshing = refreshing
        self.applyLook()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
    {
        super.traitCollectionDidChange(previousTraitCollection)
        self.applyLook()
    }
    
    fileprivate func applyLook()
    {
        let look = SiloTheme.look(for: self.traitCollection.userInterfaceStyle)
        
        self.headlineLabel.textColor = look.text
        self.detailLabel.textColor = look.textMuted
        
        var configuration = UIButton.Configuration.filled()
        configuration.title = self.isRefreshing ? NSLocalizedString("Refreshing…", comment: "") : NSLocalizedString("Refresh all", comment: "")
        configuration.baseBackgroundColor = look.accent
        configuration.baseForegroundColor = look.accentInk
        configuration.background.cornerRadius = look.radiusControl
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = SiloFont.uiFont(.headline)
            return outgoing
        }
        self.refreshButton.configuration = configuration
        self.refreshButton.isEnabled = !self.isRefreshing
    }
}

final class UpdatesCollectionHeaderView: UICollectionReusableView
{
    let button = PillButton(type: .system)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.button.translatesAutoresizingMaskIntoConstraints = false
        self.button.setTitle(">", for: .normal)
        self.addSubview(self.button)
        
        NSLayoutConstraint.activate([self.button.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -20),
                                     self.button.topAnchor.constraint(equalTo: self.topAnchor),
                                     self.button.widthAnchor.constraint(equalToConstant: 50),
                                     self.button.heightAnchor.constraint(equalToConstant: 26)])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
