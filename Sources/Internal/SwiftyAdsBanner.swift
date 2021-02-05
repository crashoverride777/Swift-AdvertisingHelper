//    The MIT License (MIT)
//
//    Copyright (c) 2015-2021 Dominik Ringler
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import GoogleMobileAds

enum BannerAdPositition {
    case top(isUsingSafeArea: Bool)
    case bottom(isUsingSafeArea: Bool)
}

protocol SwiftyAdsBannerType: AnyObject {
    func prepare(in viewController: UIViewController,
                 adUnitIdType: SwiftyAdsAdUnitIdType,
                 position: BannerAdPositition,
                 animationDuration: TimeInterval,
                 onOpen: (() -> Void)?,
                 onClose: (() -> Void)?,
                 onError: ((Error) -> Void)?)
    func show(isLandscape: Bool)
    func remove()
}

final class SwiftyAdsBanner: NSObject {
    
    // MARK: - Properties
    
    private let adUnitId: String
    private let request: () -> GADRequest
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?
    
    private var bannerView: GADBannerView?
    private var position: BannerAdPositition = .bottom(isUsingSafeArea: true)
    private var animationDuration: TimeInterval = 1.4
    private var bannerViewConstraint: NSLayoutConstraint?
    private var animator: UIViewPropertyAnimator?
    private var currentView: UIView?
    private var visibleConstant: CGFloat = 0
    private var hiddenConstant: CGFloat = 400
    
    // MARK: - Initialization
    
    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
        super.init()
    }
}
 
// MARK: - SwiftyAdBannerType

extension SwiftyAdsBanner: SwiftyAdsBannerType {
    
    func prepare(in viewController: UIViewController,
                 adUnitIdType: SwiftyAdsAdUnitIdType,
                 position: BannerAdPositition,
                 animationDuration: TimeInterval,
                 onOpen: (() -> Void)?,
                 onClose: (() -> Void)?,
                 onError: ((Error) -> Void)?) {
        self.position = position
        self.animationDuration = animationDuration
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        
        // Remove old banners if needed
        remove()
        
        // Update current view reference
        currentView = viewController.view
        
        // Create new banner ad
        bannerView = GADBannerView()
        
        guard let bannerView = bannerView else {
            return
        }

        // Set ad unit id
        if case .custom(let adUnitId) = adUnitIdType {
            bannerView.adUnitID = adUnitId
        } else {
            bannerView.adUnitID = adUnitId
        }

        // Set the banner view delegate
        bannerView.delegate = self

        // Set the root view controller that will display the banner
        bannerView.rootViewController = viewController

        // Add banner view to view controller
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(bannerView)
         
        // Add constraints
        // We don't give the banner a width or height constraint, as the provided ad size will give the banner
        // an intrinsic content size
        switch position {
        case .top(let isUsingSafeArea):
            if isUsingSafeArea {
                bannerViewConstraint = bannerView.topAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor)
            } else {
                bannerViewConstraint = bannerView.topAnchor.constraint(equalTo: viewController.view.topAnchor)
            }
            
        case .bottom(let isUsingSafeArea):
            if let tabBarController = viewController as? UITabBarController {
                tabBarController.view.bringSubviewToFront(tabBarController.tabBar)
                bannerViewConstraint = bannerView.bottomAnchor.constraint(equalTo: tabBarController.tabBar.safeAreaLayoutGuide.topAnchor)
            } else {
                if isUsingSafeArea {
                    bannerViewConstraint = bannerView.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor)
                } else {
                    bannerViewConstraint = bannerView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
                }
            }
        }

        guard let bannerViewConstraint = bannerViewConstraint else {
            fatalError("SwiftyAdsBanner constraint not set")
        }

        // Activate constraints
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.centerXAnchor),
            bannerViewConstraint
        ])

        // Move banner off screen
        animateToOffScreenPosition(bannerView, from: viewController, position: position, animated: false)
    }

    func show(isLandscape: Bool) {
        guard let bannerView = bannerView else {
            return
        }

        guard let currentView = currentView else {
            return
        }

        // Determine the view width to use for the ad width.
        let frame = { () -> CGRect in
            switch position {
            case .top(let isUsingSafeArea), .bottom(let isUsingSafeArea):
                if isUsingSafeArea {
                    return currentView.frame.inset(by: currentView.safeAreaInsets)
                } else {
                    return currentView.frame
                }
            }
        }()

        // Get Adaptive GADAdSize and set the ad view.
        if isLandscape {
            bannerView.adSize = GADLandscapeAnchoredAdaptiveBannerAdSizeWithWidth(frame.size.width)
        } else {
            bannerView.adSize = GADPortraitAnchoredAdaptiveBannerAdSizeWithWidth(frame.size.width)
        }

        // Create an ad request and load the adaptive banner ad.
        bannerView.load(request())
    }
    
    func remove() {
        guard bannerView != nil else {
            return
        }
        
        bannerView?.delegate = nil
        bannerView?.removeFromSuperview()
        bannerView = nil
        bannerViewConstraint = nil
        currentView = nil
        onClose?()
    }
}

// MARK: - GADBannerViewDelegate

extension SwiftyAdsBanner: GADBannerViewDelegate {

    func bannerViewDidRecordImpression(_ bannerView: GADBannerView) {
        print("SwiftyAdsBanner did record impression for ad: \(bannerView)")
    }
    
    func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
        print("SwiftyAdsBanner did receive ad from: \(bannerView.responseInfo?.adNetworkClassName ?? "not found")")
        animateToOnScreenPosition(bannerView, from: bannerView.rootViewController)
    }

    func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
        animateToOffScreenPosition(bannerView, from: bannerView.rootViewController, position: position)
        onError?(error)
    }
}

// MARK: - Private Methods

private extension SwiftyAdsBanner {

    func animateToOnScreenPosition(_ bannerAd: GADBannerView,
                                   from viewController: UIViewController?,
                                   completion: (() -> Void)? = nil) {
        // We can only animate the banner to its on-screen position with a valid view controller
        guard let viewController = viewController else {
            return
        }
        
        // We can only animate the banner to its on-screen position if its not already visible
        guard let bannerViewConstraint = bannerViewConstraint, bannerViewConstraint.constant != visibleConstant else {
            return
        }
        
        // Animate banner
        bannerAd.isHidden = false
        bannerViewConstraint.constant = visibleConstant
        
        stopCurrentAnimatorAnimations()
        animator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeOut) {
            viewController.view.layoutIfNeeded()
        }
        
        animator?.addCompletion { [weak self] _ in
            guard let self = self else { return }
            self.onOpen?()
            completion?()
        }

        animator?.startAnimation()
    }
    
    func animateToOffScreenPosition(_ bannerAd: GADBannerView,
                                    from viewController: UIViewController?,
                                    position: BannerAdPositition,
                                    animated: Bool = true,
                                    completion: (() -> Void)? = nil) {
        // We can only animate the banner to its off-screen position with a valid view controller
        guard let viewController = viewController else {
            return
        }
        
        // We can only animate the banner to its off-screen position if its already visible
        guard let bannerViewConstraint = bannerViewConstraint, bannerViewConstraint.constant == visibleConstant else {
            return
        }
        
        // Get banner off-screen constant
        let newConstant: CGFloat
        switch position {
        case .top:
            newConstant = -hiddenConstant
        case .bottom:
            newConstant = hiddenConstant
        }

        // Only animate the banner if we want it animated
        guard animated else {
            bannerAd.isHidden = true
            bannerViewConstraint.constant = newConstant
            return
        }
        
        // Animate banner
        bannerViewConstraint.constant = newConstant
        stopCurrentAnimatorAnimations()
        animator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeOut) {
            viewController.view.layoutIfNeeded()
        }
        
        animator?.addCompletion { [weak self] _ in
            guard let self = self else { return }
            bannerAd.isHidden = true
            self.onClose?()
            completion?()
        }
        
        animator?.startAnimation()
    }

    func stopCurrentAnimatorAnimations() {
        animator?.stopAnimation(false)
        animator?.finishAnimation(at: .current)
    }
}
