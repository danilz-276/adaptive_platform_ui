import Flutter
import UIKit

private final class LayoutAwareTabBarContainerView: UIView {
    var gradientLayer: CAGradientLayer?
    var onTraitChange: (() -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?
    var onWindowAttached: (() -> Void)?
    private var lastReportedWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()

        // Match container bounds so the gradient doesn't get clipped by Flutter's PlatformView wrapper
        gradientLayer?.frame = bounds

        guard window != nil else { return }

        let width = bounds.width
        guard width > 0 else { return }
        guard abs(width - lastReportedWidth) > 0.5 else { return }

        lastReportedWidth = width
        onWidthChanged?(width)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onWindowAttached?() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            onTraitChange?()
        }
    }
}

class iOS26TabBarPlatformView: NSObject, FlutterPlatformView, UITabBarDelegate {
    private let channel: FlutterMethodChannel
    private let container: LayoutAwareTabBarContainerView
    private var tabBar: UITabBar?
    private var enableBlur: Bool = true
    private var fadeColor: UIColor? = nil
    private var minimizeBehavior: Int = 3 // automatic
    private var currentLabels: [String] = []
    private var currentSymbols: [String] = []
    private var currentSelectedSymbols: [String] = []
    private var currentAssetIcons: [String] = []
    private var currentSelectedAssetIcons: [String] = []
    private var currentFileIcons: [String] = []
    private var currentSelectedFileIcons: [String] = []
    private var currentNetworkIcons: [String] = []
    private var currentSelectedNetworkIcons: [String] = []
    private var currentSearchFlags: [Bool] = []
    private var currentBadgeCounts: [Int?] = []
    private var currentBadgeTexts: [String?] = []
    private var currentBadgeColors: [Int?] = []
    private var currentBadgeTextColors: [Int?] = []
    private let imageCache = NSCache<NSString, UIImage>()
    private var currentTint: UIColor? = nil
    private var currentUnselectedTint: UIColor? = nil
    private var builtSearchFlags: [Bool] = []

    /// Applies a badge to a tab bar item from the Flutter-provided styling.
    /// Precedence: a non-empty [text] wins over [count]; otherwise a positive
    /// [count] is shown; otherwise no badge. [colorARGB] sets the badge
    /// background (nil = system default red), [textColorARGB] the glyph color
    /// (nil = platform default). A transparent background + a colored glyph
    /// renders a clean dot (e.g. badgeText "●").
    private static func applyBadge(to item: UITabBarItem, count: Int?, text: String?, colorARGB: Int?, textColorARGB: Int?) {
        let value: String?
        if let text = text, !text.isEmpty {
            value = text
        } else if let count = count, count > 0 {
            value = count > 99 ? "99+" : String(count)
        } else {
            value = nil
        }
        item.badgeValue = value
        item.badgeColor = colorARGB != nil ? colorFromARGB(colorARGB!) : nil
        if let argb = textColorARGB {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: colorFromARGB(argb)]
            item.setBadgeTextAttributes(attrs, for: .normal)
            item.setBadgeTextAttributes(attrs, for: .selected)
        } else {
            item.setBadgeTextAttributes(nil, for: .normal)
            item.setBadgeTextAttributes(nil, for: .selected)
        }
    }

    private static func badgeAt<T>(_ arr: [T?], _ i: Int) -> T? {
        return i < arr.count ? arr[i] : nil
    }

    init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_tab_bar_\(viewId)",
            binaryMessenger: messenger
        )
        self.container = LayoutAwareTabBarContainerView(frame: frame)

        var labels: [String] = []
        var symbols: [String] = []
        var selectedSymbols: [String] = []
        var assetIcons: [String] = []
        var selectedAssetIcons: [String] = []
        var fileIcons: [String] = []
        var selectedFileIcons: [String] = []
        var networkIcons: [String] = []
        var selectedNetworkIcons: [String] = []
        var searchFlags: [Bool] = []
        var badgeCounts: [Int?] = []
        var badgeTexts: [String?] = []
        var badgeColors: [Int?] = []
        var badgeTextColors: [Int?] = []
        var selectedIndex: Int = 0
        var isDark: Bool = false
        var isRtl: Bool = false
        var tint: UIColor? = nil
        var bg: UIColor? = nil
        var minimize: Int = 3 // automatic
        var blurEnabled: Bool = true

        var unselectedTint: UIColor? = nil

        if let dict = args as? [String: Any] {
            labels = (dict["labels"] as? [String]) ?? []
            symbols = (dict["sfSymbols"] as? [String]) ?? []
            selectedSymbols = (dict["selectedSfSymbols"] as? [String]) ?? []
            assetIcons = (dict["assetIcons"] as? [String]) ?? []
            selectedAssetIcons = (dict["selectedAssetIcons"] as? [String]) ?? []
            fileIcons = (dict["fileIcons"] as? [String]) ?? []
            selectedFileIcons = (dict["selectedFileIcons"] as? [String]) ?? []
            networkIcons = (dict["networkIcons"] as? [String]) ?? []
            selectedNetworkIcons = (dict["selectedNetworkIcons"] as? [String]) ?? []
            searchFlags = (dict["searchFlags"] as? [Bool]) ?? []
            if let badgeData = dict["badgeCounts"] as? [NSNumber?] {
                badgeCounts = badgeData.map { $0?.intValue }
            }
            if let arr = dict["badgeTexts"] as? [Any?] {
                badgeTexts = arr.map { $0 as? String }
            }
            if let arr = dict["badgeColors"] as? [NSNumber?] {
                badgeColors = arr.map { $0?.intValue }
            }
            if let arr = dict["badgeTextColors"] as? [NSNumber?] {
                badgeTextColors = arr.map { $0?.intValue }
            }
            if let v = dict["selectedIndex"] as? NSNumber { selectedIndex = v.intValue }
            if let v = dict["isDark"] as? NSNumber { isDark = v.boolValue }
            if let v = dict["isRtl"] as? NSNumber { isRtl = v.boolValue }
            if let n = dict["tint"] as? NSNumber { tint = Self.colorFromARGB(n.intValue) }
            if let n = dict["unselectedItemTint"] as? NSNumber { unselectedTint = Self.colorFromARGB(n.intValue) }
            if let n = dict["backgroundColor"] as? NSNumber { bg = Self.colorFromARGB(n.intValue) }
            if let m = dict["minimizeBehavior"] as? NSNumber { minimize = m.intValue }
            if let b = dict["enableBlur"] as? NSNumber { blurEnabled = b.boolValue }
            if let n = dict["fadeColor"] as? NSNumber { self.fadeColor = Self.colorFromARGB(n.intValue) }
        }

        super.init()
        self.enableBlur = blurEnabled

        container.backgroundColor = .clear
        if #available(iOS 13.0, *) {
            container.overrideUserInterfaceStyle = isDark ? .dark : .light
        }

        if blurEnabled {
            setupGradient()
        }

        // Create single tab bar
        let bar = UITabBar(frame: .zero)
        tabBar = bar
        bar.delegate = self
        bar.isTranslucent = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        let semanticAttribute: UISemanticContentAttribute = isRtl
            ? .forceRightToLeft
            : .forceLeftToRight
        bar.semanticContentAttribute = semanticAttribute
        // The iOS 26 selected Liquid Glass content is portal-backed and reads the trait direction.
        // Override both APIs so the app locale wins when it differs from the device locale.
        if #available(iOS 17.0, *) {
            bar.traitOverrides.layoutDirection = isRtl ? .rightToLeft : .leftToRight
        }
        container.semanticContentAttribute = semanticAttribute

        Self.applyAppearance(to: bar, tint: tint, unselectedTint: unselectedTint)
        if let bg = bg { bar.barTintColor = bg }

        self.currentTint = tint
        self.currentUnselectedTint = unselectedTint
        self.minimizeBehavior = minimize
        self.currentLabels = labels
        self.currentSymbols = symbols
        self.currentSelectedSymbols = selectedSymbols
        self.currentAssetIcons = assetIcons
        self.currentSelectedAssetIcons = selectedAssetIcons
        self.currentFileIcons = fileIcons
        self.currentSelectedFileIcons = selectedFileIcons
        self.currentNetworkIcons = networkIcons
        self.currentSelectedNetworkIcons = selectedNetworkIcons
        self.currentSearchFlags = searchFlags
        self.currentBadgeCounts = badgeCounts
        self.currentBadgeTexts = badgeTexts
        self.currentBadgeColors = badgeColors
        self.currentBadgeTextColors = badgeTextColors
        applyItems(selectedIndex: selectedIndex, forceRecreate: true)

        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Apply minimize behavior if available
        self.applyMinimizeBehavior()

        container.onWidthChanged = { [weak self] _ in
            self?.handleContainerWidthChange()
        }
        container.onWindowAttached = { [weak self] in
            self?.channel.invokeMethod("intrinsicSizeChanged", arguments: nil)
        }

        // Setup method call handler
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(nil); return }
            self.handleMethodCall(call, result: result)
        }
    }

    private func applyMinimizeBehavior() {
        // Note: UITabBarController.tabBarMinimizeBehavior is the official iOS 26+ API
        // However, since we're using a standalone UITabBar in a platform view,
        // we need to implement custom minimize behavior
        //
        // The minimize behavior should be controlled at the Flutter level
        // by adjusting the tab bar's height/visibility based on scroll events
        //
        // This method stores the behavior preference for future use
        // The actual minimization animation should be handled by Flutter
    }

    private func handleContainerWidthChange() {
        guard let bar = self.tabBar else { return }

        // A standalone UITabBar hosted in a platform view can lay out once
        // before it has its final width. Rebuild against the real container
        // width so item labels and spacing are computed from the final bounds.
        if #available(iOS 26.0, *) {
            applyItems(selectedIndex: nil, forceRecreate: true)
        }

        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        container.setNeedsLayout()
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getIntrinsicSize":
            // Bar content height only (without the bottom safe area). Flutter adds
            // its own MediaQuery inset, which is reliable even before the view
            // is attached to a window.
            if let bar = self.tabBar {
                let size = bar.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                // sizeThatFits already includes the home-indicator area once the bar is
                // in a window; strip it so only the bar itself is reported.
                let inset = self.container.window?.safeAreaInsets.bottom ?? 0
                var barHeight = size.height
                if inset > 0 && barHeight - inset >= 44 { barHeight -= inset }
                result(["width": Double(size.width), "height": Double(barHeight > 0 ? barHeight : 49.0)])
            } else {
                result(["width": Double(self.container.bounds.width), "height": 49.0])
            }

        case "setItems":
            guard let args = call.arguments as? [String: Any],
                  let labels = args["labels"] as? [String],
                  let symbols = args["sfSymbols"] as? [String] else {
                result(FlutterError(code: "bad_args", message: "Missing items", details: nil))
                return
            }

            let selectedSymbols = (args["selectedSfSymbols"] as? [String]) ?? []
            let assetIcons = (args["assetIcons"] as? [String]) ?? []
            let selectedAssetIcons = (args["selectedAssetIcons"] as? [String]) ?? []
            let fileIcons = (args["fileIcons"] as? [String]) ?? []
            let selectedFileIcons = (args["selectedFileIcons"] as? [String]) ?? []
            let networkIcons = (args["networkIcons"] as? [String]) ?? []
            let selectedNetworkIcons = (args["selectedNetworkIcons"] as? [String]) ?? []
            let searchFlags = (args["searchFlags"] as? [Bool]) ?? []
            let selectedIndex = (args["selectedIndex"] as? NSNumber)?.intValue ?? 0
            var badgeCounts: [Int?] = []
            if let badgeData = args["badgeCounts"] as? [NSNumber?] {
                badgeCounts = badgeData.map { $0?.intValue }
            }
            let badgeTexts: [String?] = (args["badgeTexts"] as? [Any?])?.map { $0 as? String } ?? []
            let badgeColors: [Int?] = (args["badgeColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []
            let badgeTextColors: [Int?] = (args["badgeTextColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []

            self.currentLabels = labels
            self.currentSymbols = symbols
            self.currentSelectedSymbols = selectedSymbols
            self.currentAssetIcons = assetIcons
            self.currentSelectedAssetIcons = selectedAssetIcons
            self.currentFileIcons = fileIcons
            self.currentSelectedFileIcons = selectedFileIcons
            self.currentNetworkIcons = networkIcons
            self.currentSelectedNetworkIcons = selectedNetworkIcons
            self.currentSearchFlags = searchFlags
            self.currentBadgeCounts = badgeCounts
            self.currentBadgeTexts = badgeTexts
            self.currentBadgeColors = badgeColors
            self.currentBadgeTextColors = badgeTextColors

            self.applyItems(selectedIndex: selectedIndex, forceRecreate: false)
            result(nil)

        case "setSelectedIndex":
            guard let args = call.arguments as? [String: Any],
                  let idx = (args["index"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "bad_args", message: "Invalid index", details: nil))
                return
            }

            if let bar = self.tabBar, let items = bar.items, idx >= 0, idx < items.count,
               bar.selectedItem !== items[idx] {
                bar.selectedItem = items[idx]
            }
            result(nil)

        case "setStyle":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_args", message: "Missing style", details: nil))
                return
            }

            var tintChanged = false
            var unselectedChanged = false
            if let n = args["tint"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                if self.currentTint != c {
                    self.currentTint = c
                    tintChanged = true
                }
            }
            if let n = args["unselectedItemTint"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                if self.currentUnselectedTint != c {
                    self.currentUnselectedTint = c
                    unselectedChanged = true
                }
            }
            if (tintChanged || unselectedChanged), let bar = self.tabBar {
                // Appearance overrides tintColor, so colors must be re-applied
                // through it; otherwise theme changes would require recreating the view.
                Self.applyAppearance(
                    to: bar,
                    tint: self.currentTint,
                    unselectedTint: self.currentUnselectedTint
                )
                if unselectedChanged {
                    // Unselected icons are pre-tinted on iOS 26, refresh them in place.
                    self.applyItems(selectedIndex: nil, forceRecreate: false)
                }
            }
            if let n = args["backgroundColor"] as? NSNumber {
                let c = Self.colorFromARGB(n.intValue)
                self.tabBar?.barTintColor = c
            }
            if let n = args["fadeColor"] as? NSNumber {
                self.fadeColor = Self.colorFromARGB(n.intValue)
                self.updateGradientColors()
            } else if args.keys.contains("fadeColor") {
                self.fadeColor = nil
                self.updateGradientColors()
            }

            result(nil)

        case "setBrightness":
            guard let args = call.arguments as? [String: Any],
                  let isDark = (args["isDark"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing isDark", details: nil))
                return
            }

            if #available(iOS 13.0, *) {
                self.container.overrideUserInterfaceStyle = isDark ? .dark : .light
            }
            self.updateGradientColors()
            result(nil)

        case "setEnableBlur":
            guard let args = call.arguments as? [String: Any],
                  let enable = (args["enableBlur"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing enableBlur", details: nil))
                return
            }

            self.enableBlur = enable
            if enable && self.container.gradientLayer == nil {
                self.setupGradient()
            } else {
                self.container.gradientLayer?.isHidden = !enable
            }
            result(nil)

        case "setDirectionality":
            guard let args = call.arguments as? [String: Any],
                  let isRtl = (args["isRtl"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing isRtl", details: nil))
                return
            }

            let attribute: UISemanticContentAttribute = isRtl
                ? .forceRightToLeft
                : .forceLeftToRight
            self.tabBar?.semanticContentAttribute = attribute
            if #available(iOS 17.0, *) {
                self.tabBar?.traitOverrides.layoutDirection = isRtl
                    ? .rightToLeft
                    : .leftToRight
            }
            self.container.semanticContentAttribute = attribute
            result(nil)

        case "setMinimizeBehavior":
            guard let args = call.arguments as? [String: Any],
                  let behavior = (args["behavior"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "bad_args", message: "Missing behavior", details: nil))
                return
            }

            self.minimizeBehavior = behavior
            self.applyMinimizeBehavior()
            result(nil)

        case "setHidden":
            guard let args = call.arguments as? [String: Any],
                  let hidden = (args["hidden"] as? NSNumber)?.boolValue else {
                result(FlutterError(code: "bad_args", message: "Missing hidden", details: nil))
                return
            }

            self.container.isHidden = hidden
            result(nil)

        case "setBadgeCounts":
            guard let args = call.arguments as? [String: Any],
                  let badgeData = args["badgeCounts"] as? [NSNumber?] else {
                result(FlutterError(code: "bad_args", message: "Missing badge counts", details: nil))
                return
            }

            let badgeCounts = badgeData.map { $0?.intValue }
            self.currentBadgeCounts = badgeCounts
            self.currentBadgeTexts = (args["badgeTexts"] as? [Any?])?.map { $0 as? String } ?? []
            self.currentBadgeColors = (args["badgeColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []
            self.currentBadgeTextColors = (args["badgeTextColors"] as? [NSNumber?])?.map { $0?.intValue } ?? []

            // Update existing tab bar items with new badge values
            if let bar = self.tabBar, let items = bar.items {
                for (index, item) in items.enumerated() {
                    Self.applyBadge(
                        to: item,
                        count: Self.badgeAt(badgeCounts, index),
                        text: Self.badgeAt(self.currentBadgeTexts, index),
                        colorARGB: Self.badgeAt(self.currentBadgeColors, index),
                        textColorARGB: Self.badgeAt(self.currentBadgeTextColors, index)
                    )
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func applyAppearance(to bar: UITabBar, tint: UIColor?, unselectedTint: UIColor?) {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear

        let unselColor = unselectedTint ?? UIColor.systemGray
        let selColor = tint ?? UIColor.systemBlue
        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.iconColor = unselColor
            layout.normal.titleTextAttributes = [.foregroundColor: unselColor]
            layout.selected.iconColor = selColor
            layout.selected.titleTextAttributes = [.foregroundColor: selColor]
        }

        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        if let tint = tint { bar.tintColor = tint }
        if let unselectedTint = unselectedTint { bar.unselectedItemTintColor = unselectedTint }
    }

    private var itemCount: Int {
        return max(
            max(currentLabels.count, currentSymbols.count),
            max(max(currentAssetIcons.count, currentFileIcons.count), currentNetworkIcons.count)
        )
    }

    private func isSearchItem(_ index: Int) -> Bool {
        return index < currentSearchFlags.count && currentSearchFlags[index]
    }

    /// Applies the current native state to the tab bar.
    /// Existing items are updated in place whenever the item structure is unchanged,
    /// which keeps the Liquid Glass selection indicator from resetting/flickering.
    /// `forceRecreate` replaces the items (needed after the first real layout width).
    private func applyItems(selectedIndex: Int?, forceRecreate: Bool) {
        guard let bar = self.tabBar else { return }

        let count = itemCount
        let searchFlags = (0..<count).map { isSearchItem($0) }
        let existing = bar.items ?? []
        let currentIndex = existing.firstIndex { $0 === bar.selectedItem } ?? 0
        let targetIndex = selectedIndex ?? currentIndex

        let canReuse = !forceRecreate
            && existing.count == count
            && builtSearchFlags == searchFlags

        let items: [UITabBarItem]
        if canReuse {
            items = existing
            for i in 0..<count { configureItem(items[i], index: i) }
        } else {
            items = (0..<count).map { i in
                let item = makeItem(index: i)
                configureItem(item, index: i)
                return item
            }
            bar.items = items
            builtSearchFlags = searchFlags
        }

        if targetIndex >= 0, targetIndex < items.count, bar.selectedItem !== items[targetIndex] {
            bar.selectedItem = items[targetIndex]
        }
    }

    private func makeItem(index i: Int) -> UITabBarItem {
        if isSearchItem(i) {
            if #available(iOS 26.0, *) {
                return UITabBarItem(tabBarSystemItem: .search, tag: i)
            }
            let searchImage = UIImage(systemName: "magnifyingglass")
            let item = UITabBarItem(title: nil, image: searchImage, selectedImage: searchImage)
            item.tag = i
            return item
        }
        let item = UITabBarItem(title: nil, image: nil, selectedImage: nil)
        item.tag = i
        return item
    }

    private func configureItem(_ item: UITabBarItem, index i: Int) {
        let title = i < currentLabels.count ? currentLabels[i] : nil

        if isSearchItem(i) {
            if let title = title, item.title != title { item.title = title }
        } else {
            let resolvedTitle = title ?? "Tab \(i + 1)"
            if item.title != resolvedTitle { item.title = resolvedTitle }

            if !configureRuntimeImages(for: item, index: i) {
                let images = resolveImages(index: i)
                if item.image !== images.normal { item.image = images.normal }
                if item.selectedImage !== images.selected { item.selectedImage = images.selected }
            }
        }

        Self.applyBadge(
            to: item,
            count: Self.badgeAt(currentBadgeCounts, i),
            text: Self.badgeAt(currentBadgeTexts, i),
            colorARGB: Self.badgeAt(currentBadgeColors, i),
            textColorARGB: Self.badgeAt(currentBadgeTextColors, i)
        )
    }

    private func resolveImages(index i: Int) -> (normal: UIImage?, selected: UIImage?) {
        let unselTint = currentUnselectedTint

        if i < currentAssetIcons.count && !currentAssetIcons[i].isEmpty {
            let rawImage = cachedAssetImage(currentAssetIcons[i])
            var selRawImage = rawImage
            if i < currentSelectedAssetIcons.count && !currentSelectedAssetIcons[i].isEmpty {
                selRawImage = cachedAssetImage(currentSelectedAssetIcons[i]) ?? rawImage
            }

            if #available(iOS 26.0, *) {
                let key = "asset:\(currentAssetIcons[i])"
                let selKey = "asset:\(i < currentSelectedAssetIcons.count && !currentSelectedAssetIcons[i].isEmpty ? currentSelectedAssetIcons[i] : currentAssetIcons[i])"
                let normal = unselTint != nil
                    ? cachedTinted(rawImage, key: key, tint: unselTint!)
                    : cachedTemplate(rawImage, key: key)
                return (normal, cachedTemplate(selRawImage, key: selKey))
            }
            return (rawImage, selRawImage)
        }

        if i < currentSymbols.count && !currentSymbols[i].isEmpty {
            let symbol = currentSymbols[i]
            let selSymbol = (i < currentSelectedSymbols.count && !currentSelectedSymbols[i].isEmpty)
                ? currentSelectedSymbols[i]
                : symbol
            let rawImage = UIImage(systemName: symbol) ?? UIImage(named: symbol)
            let selRawImage = UIImage(systemName: selSymbol) ?? UIImage(named: selSymbol)

            if #available(iOS 26.0, *) {
                let normal = unselTint != nil
                    ? cachedTinted(rawImage, key: "symbol:\(symbol)", tint: unselTint!)
                    : cachedTemplate(rawImage, key: "symbol:\(symbol)")
                return (normal, cachedTemplate(selRawImage, key: "symbol:\(selSymbol)"))
            }
            return (rawImage, selRawImage)
        }

        return (nil, nil)
    }

    private func cachedAssetImage(_ assetName: String) -> UIImage? {
        let cacheKey = "asset:\(assetName)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        let lookupKey = FlutterDartProject.lookupKey(forAsset: assetName)
        guard let raw = UIImage(named: lookupKey) else { return nil }
        let resized = resizeImage(image: raw)
        imageCache.setObject(resized, forKey: cacheKey)
        return resized
    }

    private func cachedTemplate(_ image: UIImage?, key: String) -> UIImage? {
        guard let image = image else { return nil }
        let cacheKey = "template:\(key)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        let template = image.withRenderingMode(.alwaysTemplate)
        imageCache.setObject(template, forKey: cacheKey)
        return template
    }

    private func cachedTinted(_ image: UIImage?, key: String, tint: UIColor) -> UIImage? {
        guard let image = image else { return nil }
        let cacheKey = "tinted:\(key):\(Self.colorKey(tint))" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        let tinted = image.withTintColor(tint, renderingMode: .alwaysOriginal)
        imageCache.setObject(tinted, forKey: cacheKey)
        return tinted
    }

    private func setupGradient() {
        container.clipsToBounds = false

        let gradientLayer = CAGradientLayer()
        // Fade from bottom (opaque) to top (transparent), matching iOS26ToolbarPlatformView
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        container.layer.insertSublayer(gradientLayer, at: 0)
        container.gradientLayer = gradientLayer
        container.onTraitChange = { [weak self] in
            self?.updateGradientColors()
        }
        updateGradientColors()
    }

    private func updateGradientColors() {
        let isDarkMode: Bool
        if #available(iOS 13.0, *) {
            isDarkMode = container.overrideUserInterfaceStyle == .dark
                || container.traitCollection.userInterfaceStyle == .dark
        } else {
            isDarkMode = false
        }
        let baseColor = self.fadeColor ?? (isDarkMode ? UIColor.black : UIColor.white)

        container.gradientLayer?.colors = [
            baseColor.withAlphaComponent(0.82).cgColor,
            baseColor.withAlphaComponent(0.7).cgColor,
            baseColor.withAlphaComponent(0.4).cgColor,
            baseColor.withAlphaComponent(0.0).cgColor,
        ]
        container.gradientLayer?.locations = [0.0, 0.4, 0.8, 1.0]
    }

    func view() -> UIView { container }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let idx = (item.tag >= 0) ? item.tag : (self.tabBar?.items?.firstIndex(of: item) ?? 0)
        channel.invokeMethod("valueChanged", arguments: ["index": idx])
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f-%.3f-%.3f-%.3f", r, g, b, a)
    }

    private static func colorFromARGB(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private func runtimeFilePath(for index: Int, selected: Bool) -> String {
        let paths = selected ? currentSelectedFileIcons : currentFileIcons
        if index < paths.count, !paths[index].isEmpty {
            return paths[index]
        }
        if selected, index < currentFileIcons.count {
            return currentFileIcons[index]
        }
        return ""
    }

    private func runtimeNetworkURL(for index: Int, selected: Bool) -> String {
        let urls = selected ? currentSelectedNetworkIcons : currentNetworkIcons
        if index < urls.count, !urls[index].isEmpty {
            return urls[index]
        }
        if selected, index < currentNetworkIcons.count {
            return currentNetworkIcons[index]
        }
        return ""
    }

    private func hasRuntimeImage(for index: Int) -> Bool {
        return !runtimeFilePath(for: index, selected: false).isEmpty ||
            !runtimeNetworkURL(for: index, selected: false).isEmpty ||
            !runtimeFilePath(for: index, selected: true).isEmpty ||
            !runtimeNetworkURL(for: index, selected: true).isEmpty
    }

    private lazy var placeholderAvatar: UIImage? = UIImage(systemName: "person.crop.circle")?
        .withRenderingMode(.alwaysOriginal)

    private func loadRuntimeImage(filePath: String, networkURL: String) -> UIImage? {
        if !filePath.isEmpty {
            let cacheKey = "avatar-file:\(filePath)" as NSString
            if let cached = imageCache.object(forKey: cacheKey) { return cached }
            if let image = UIImage(contentsOfFile: filePath) {
                let avatar = avatarImage(from: image)
                imageCache.setObject(avatar, forKey: cacheKey)
                return avatar
            }
        }

        if !networkURL.isEmpty {
            let cacheKey = "avatar-net:\(networkURL)" as NSString
            if let cached = imageCache.object(forKey: cacheKey) { return cached }
            if let raw = imageCache.object(forKey: networkURL as NSString) {
                let avatar = avatarImage(from: raw)
                imageCache.setObject(avatar, forKey: cacheKey)
                return avatar
            }
        }

        return nil
    }

    private func fetchNetworkImageIfNeeded(
        urlString: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard !urlString.isEmpty else {
            completion(nil)
            return
        }

        if let cached = imageCache.object(forKey: urlString as NSString) {
            completion(avatarImage(from: cached))
            return
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            self.imageCache.setObject(image, forKey: urlString as NSString)
            let avatar = self.avatarImage(from: image)
            DispatchQueue.main.async {
                completion(avatar)
            }
        }.resume()
    }

    private func configureRuntimeImages(for item: UITabBarItem, index: Int) -> Bool {
        guard hasRuntimeImage(for: index) else { return false }

        let unselectedFile = runtimeFilePath(for: index, selected: false)
        let selectedFile = runtimeFilePath(for: index, selected: true)
        let unselectedNetwork = runtimeNetworkURL(for: index, selected: false)
        let selectedNetwork = runtimeNetworkURL(for: index, selected: true)

        let unselectedImage = loadRuntimeImage(filePath: unselectedFile, networkURL: unselectedNetwork)
        let selectedImage = loadRuntimeImage(filePath: selectedFile, networkURL: selectedNetwork)

        let normal = unselectedImage ?? placeholderAvatar
        let selected = selectedImage ?? unselectedImage ?? placeholderAvatar
        if item.image !== normal { item.image = normal }
        if item.selectedImage !== selected { item.selectedImage = selected }

        if unselectedImage == nil && !unselectedNetwork.isEmpty {
            fetchNetworkImageIfNeeded(urlString: unselectedNetwork) { [weak item] avatar in
                guard let item = item, let avatar = avatar else { return }
                item.image = avatar.withRenderingMode(.alwaysOriginal)
                if selectedImage == nil && selectedNetwork.isEmpty && selectedFile.isEmpty {
                    item.selectedImage = avatar.withRenderingMode(.alwaysOriginal)
                }
            }
        }

        if selectedImage == nil && !selectedNetwork.isEmpty {
            fetchNetworkImageIfNeeded(urlString: selectedNetwork) { [weak item] avatar in
                guard let item = item, let avatar = avatar else { return }
                item.selectedImage = avatar.withRenderingMode(.alwaysOriginal)
            }
        }

        return true
    }

    private func resizeImage(image: UIImage, targetSize: CGSize = CGSize(width: 26, height: 26)) -> UIImage {
        let size = image.size
        if size.width <= targetSize.width && size.height <= targetSize.height {
            return image
        }
        
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        if #available(iOS 10.0, *) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { context in
                image.draw(in: rect)
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(newSize, false, UIScreen.main.scale)
            image.draw(in: rect)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return newImage ?? image
        }
    }

    private func avatarImage(from image: UIImage, targetSize: CGSize = CGSize(width: 26, height: 26)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: targetSize)).addClip()

            let aspectFillScale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * aspectFillScale, height: image.size.height * aspectFillScale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2.0,
                y: (targetSize.height - scaledSize.height) / 2.0
            )

            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }.withRenderingMode(.alwaysOriginal)
    }
}

class iOS26TabBarViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26TabBarPlatformView(
            frame: frame,
            viewId: viewId,
            args: args,
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
