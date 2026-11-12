import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../adaptive_scaffold.dart';

/// Native iOS 26 tab bar using UITabBar platform view
class IOS26NativeTabBar extends StatefulWidget {
  const IOS26NativeTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    this.tint,
    this.unselectedItemTint,
    this.backgroundColor,
    this.height,
    this.minimizeBehavior = TabBarMinimizeBehavior.automatic,
    this.showNativeView = true,
    this.hidden = false,
    this.enableBlur = true,
    this.fadeColor,
    this.isDark,
    this.maxWidth,
    this.onHeightChanged,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Color? tint;
  final Color? unselectedItemTint;
  final Color? backgroundColor;

  /// Custom base color for the Liquid Glass gradient fade.
  /// When null, defaults to black in dark mode and white in light mode.
  final Color? fadeColor;
  final double? height;
  final bool showNativeView;

  /// Explicitly control dark/light appearance.
  /// If null, derives from MediaQuery.platformBrightnessOf(context).
  final bool? isDark;

  /// Whether the native tab bar is hidden.
  /// Use this to hide the tab bar when showing modal bottom sheets
  /// to prevent native platform views from bleeding through.
  final bool hidden;

  /// Whether to enable native Liquid Glass blur effect behind the tab bar.
  final bool enableBlur;

  /// Maximum width of the tab bar. When the available width is larger
  /// (iPad, wide windows), the bar is centered instead of stretched.
  final double? maxWidth;

  /// Called with the total height (bar + bottom safe area) whenever it changes,
  /// so the host can pad its content to match the native bar.
  final ValueChanged<double>? onHeightChanged;

  /// Tab bar minimize behavior (iOS 26+)
  /// Controls how the tab bar minimizes when scrolling
  final TabBarMinimizeBehavior minimizeBehavior;

  @override
  State<IOS26NativeTabBar> createState() => _IOS26NativeTabBarState();
}

class _IOS26NativeTabBarState extends State<IOS26NativeTabBar> {
  MethodChannel? _channel;
  Timer? _selectionResyncTimer;
  int? _lastIndex;
  int? _lastTint;
  int? _lastUnselectedTint;
  int? _lastBg;
  bool? _lastIsDark;
  bool? _lastIsRtl;
  double? _intrinsicHeight;
  List<String>? _lastLabels;
  List<String>? _lastSymbols;
  List<String>? _lastSelectedSymbols;
  List<String>? _lastAssetIcons;
  List<String>? _lastSelectedAssetIcons;
  List<String>? _lastFileIcons;
  List<String>? _lastSelectedFileIcons;
  List<String>? _lastNetworkIcons;
  List<String>? _lastSelectedNetworkIcons;
  List<int?>? _lastBadgeCounts;
  List<String?>? _lastBadgeTexts;
  List<int?>? _lastBadgeColors;
  List<int?>? _lastBadgeTextColors;
  TabBarMinimizeBehavior? _lastMinimizeBehavior;
  bool? _lastHidden;
  bool? _lastEnableBlur;
  int? _lastFadeColor;

  bool get _isDark =>
      widget.isDark ??
      (MediaQuery.platformBrightnessOf(context) == Brightness.dark);
  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;
  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  @override
  void didUpdateWidget(covariant IOS26NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncDirectionalityIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _selectionResyncTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  int _colorToARGB(Color color) {
    // Resolve CupertinoDynamicColor if needed
    Color resolvedColor = color;
    if (color is CupertinoDynamicColor) {
      // Resolve based on current brightness
      final brightness = _isDark ? Brightness.dark : Brightness.light;
      resolvedColor = brightness == Brightness.dark
          ? color.darkColor
          : color.color;
    }

    return ((resolvedColor.a * 255.0).round() & 0xff) << 24 |
        ((resolvedColor.r * 255.0).round() & 0xff) << 16 |
        ((resolvedColor.g * 255.0).round() & 0xff) << 8 |
        ((resolvedColor.b * 255.0).round() & 0xff);
  }

  /// Extract SF Symbol name from an icon value.
  /// Returns empty string for non-SF-Symbol icons (asset paths, IconData, widgets).
  String _extractSymbol(Object? icon) {
    if (icon is String && !icon.contains('/')) return icon;
    return '';
  }

  /// Extract asset path from an icon value.
  /// Supports AssetImage, ImageIcon(AssetImage), and string paths containing '/'.
  /// Returns empty string for SF Symbols or other icon types.
  String _extractAssetPath(Object? icon) {
    if (icon is AssetImage) return icon.assetName;
    if (icon is ImageIcon && icon.image is AssetImage) {
      return (icon.image as AssetImage).assetName;
    }
    if (icon is String && icon.contains('/')) return icon;
    return '';
  }

  String _extractFilePath(Object? icon) {
    if (icon is FileImage) return icon.file.path;
    if (icon is ImageIcon && icon.image is FileImage) {
      return (icon.image as FileImage).file.path;
    }
    return '';
  }

  String _extractNetworkUrl(Object? icon) {
    if (icon is NetworkImage) return icon.url;
    if (icon is ImageIcon && icon.image is NetworkImage) {
      return (icon.image as NetworkImage).url;
    }
    return '';
  }

  List<String> _mapSymbols() =>
      widget.destinations.map((e) => _extractSymbol(e.icon)).toList();

  List<String> _mapSelectedSymbols() => widget.destinations
      .map((e) => _extractSymbol(e.selectedIcon ?? e.icon))
      .toList();

  List<String> _mapAssetIcons() =>
      widget.destinations.map((e) => _extractAssetPath(e.icon)).toList();

  List<String> _mapSelectedAssetIcons() => widget.destinations
      .map((e) => _extractAssetPath(e.selectedIcon ?? e.icon))
      .toList();

  List<String> _mapFileIcons() =>
      widget.destinations.map((e) => _extractFilePath(e.icon)).toList();

  List<String> _mapSelectedFileIcons() => widget.destinations
      .map((e) => _extractFilePath(e.selectedIcon ?? e.icon))
      .toList();

  List<String> _mapNetworkIcons() =>
      widget.destinations.map((e) => _extractNetworkUrl(e.icon)).toList();

  List<String> _mapSelectedNetworkIcons() => widget.destinations
      .map((e) => _extractNetworkUrl(e.selectedIcon ?? e.icon))
      .toList();

  // Native badge styling: badge content + colors mapped to the
  // native side (UITabBarItem.badgeValue / .badgeColor / badge text attrs).
  List<String?> _mapBadgeTexts() =>
      widget.destinations.map((e) => e.badgeText).toList();

  List<int?> _mapBadgeColors() => widget.destinations
      .map((e) => e.badgeColor != null ? _colorToARGB(e.badgeColor!) : null)
      .toList();

  List<int?> _mapBadgeTextColors() => widget.destinations
      .map(
        (e) =>
            e.badgeTextColor != null ? _colorToARGB(e.badgeTextColor!) : null,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      final labels = widget.destinations.map((e) => e.label).toList();
      final symbols = _mapSymbols();
      final selectedSymbols = _mapSelectedSymbols();
      final assetIcons = _mapAssetIcons();
      final selectedAssetIcons = _mapSelectedAssetIcons();
      final fileIcons = _mapFileIcons();
      final selectedFileIcons = _mapSelectedFileIcons();
      final networkIcons = _mapNetworkIcons();
      final selectedNetworkIcons = _mapSelectedNetworkIcons();

      final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
      final badgeCounts = widget.destinations.map((e) => e.badgeCount).toList();
      final badgeTexts = _mapBadgeTexts();
      final badgeColors = _mapBadgeColors();
      final badgeTextColors = _mapBadgeTextColors();
      final spacerFlags = widget.destinations
          .map((e) => e.addSpacerAfter)
          .toList();

      final creationParams = <String, dynamic>{
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': badgeTexts,
        'badgeColors': badgeColors,
        'badgeTextColors': badgeTextColors,
        'spacerFlags': spacerFlags,
        'selectedIndex': widget.selectedIndex,
        'isDark': _isDark,
        'isRtl': _isRtl,
        'minimizeBehavior': widget.minimizeBehavior.index,
        'enableBlur': widget.enableBlur,
        if (_effectiveTint != null) 'tint': _colorToARGB(_effectiveTint!),
        if (widget.unselectedItemTint != null)
          'unselectedItemTint': _colorToARGB(widget.unselectedItemTint!),
        if (widget.backgroundColor != null)
          'backgroundColor': _colorToARGB(widget.backgroundColor!),
        if (widget.fadeColor != null)
          'fadeColor': _colorToARGB(widget.fadeColor!),
      };

      final platformView = widget.showNativeView
          ? UiKitView(
              viewType: 'adaptive_platform_ui/ios26_tab_bar',
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onCreated,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            )
          : const SizedBox.shrink();

      final bottomPadding = MediaQuery.paddingOf(context).bottom;
      final h = widget.height ?? ((_intrinsicHeight ?? 49.0) + bottomPadding);
      _reportHeight(h);
      final bar = SizedBox(height: h, child: platformView);
      final maxWidth = widget.maxWidth;
      if (maxWidth == null) return bar;
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: bar,
        ),
      );
    }

    // Fallback for non-iOS
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: widget.height ?? (50.0 + bottomPadding),
      child: Container(
        color:
            widget.backgroundColor ??
            CupertinoColors.systemBackground.resolveFrom(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            widget.destinations.length,
            (index) => CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => widget.onTap(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.circle,
                    color: index == widget.selectedIndex
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.systemGrey,
                  ),
                  Text(
                    widget.destinations[index].label,
                    style: TextStyle(
                      fontSize: 10,
                      color: index == widget.selectedIndex
                          ? CupertinoColors.activeBlue
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('adaptive_platform_ui/ios26_tab_bar_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    _lastIndex = widget.selectedIndex;
    _lastHidden = false;
    _lastTint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    _lastUnselectedTint = widget.unselectedItemTint != null
        ? _colorToARGB(widget.unselectedItemTint!)
        : null;
    _lastBg = widget.backgroundColor != null
        ? _colorToARGB(widget.backgroundColor!)
        : null;
    _lastFadeColor = widget.fadeColor != null
        ? _colorToARGB(widget.fadeColor!)
        : null;
    _lastIsDark = _isDark;
    _lastIsRtl = _isRtl;
    _lastMinimizeBehavior = widget.minimizeBehavior;
    _lastEnableBlur = widget.enableBlur;
    _cacheItems();
    _requestIntrinsicSize();
    // Native side was created from creationParams; only push what changed since.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _channel != ch) return;
      _requestIntrinsicSize();
      _syncBrightnessIfNeeded();
      _syncPropsToNativeIfNeeded();
    });
  }

  double? _lastReportedHeight;

  void _reportHeight(double height) {
    if (widget.onHeightChanged == null || _lastReportedHeight == height) return;
    _lastReportedHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHeightChanged?.call(height);
    });
  }

  Future<T?> _invoke<T>(MethodChannel ch, String method, [Object? args]) async {
    if (_channel != ch) return null;
    try {
      return await ch.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'intrinsicSizeChanged') {
      _requestIntrinsicSize();
      return null;
    }
    if (call.method == 'valueChanged') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      if (idx != null) {
        // Native already shows the tapped tab. If the app ignores the tap
        // (guards, locks) and never rebuilds, re-sync so both sides agree.
        _lastIndex = null;
        widget.onTap(idx);
        _selectionResyncTimer?.cancel();
        _selectionResyncTimer = Timer(const Duration(milliseconds: 400), () {
          if (mounted) _syncPropsToNativeIfNeeded();
        });
      }
    }
    return null;
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    final idx = widget.selectedIndex;
    final tint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    final unselectedTint = widget.unselectedItemTint != null
        ? _colorToARGB(widget.unselectedItemTint!)
        : null;
    final bg = widget.backgroundColor != null
        ? _colorToARGB(widget.backgroundColor!)
        : null;
    final fadeColor = widget.fadeColor != null
        ? _colorToARGB(widget.fadeColor!)
        : null;

    if (_lastIndex != idx) {
      _lastIndex = idx;
      await _invoke(ch, 'setSelectedIndex', {'index': idx});
    }

    final style = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastUnselectedTint != unselectedTint && unselectedTint != null) {
      style['unselectedItemTint'] = unselectedTint;
      _lastUnselectedTint = unselectedTint;
    }
    if (_lastBg != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBg = bg;
    }
    if (_lastFadeColor != fadeColor) {
      style['fadeColor'] = fadeColor;
      _lastFadeColor = fadeColor;
    }
    if (style.isNotEmpty) {
      await _invoke(ch, 'setStyle', style);
    }

    // Items update (for hot reload or dynamic changes)
    final labels = widget.destinations.map((e) => e.label).toList();
    final symbols = _mapSymbols();
    final selectedSymbols = _mapSelectedSymbols();
    final assetIcons = _mapAssetIcons();
    final selectedAssetIcons = _mapSelectedAssetIcons();
    final fileIcons = _mapFileIcons();
    final selectedFileIcons = _mapSelectedFileIcons();
    final networkIcons = _mapNetworkIcons();
    final selectedNetworkIcons = _mapSelectedNetworkIcons();
    final searchFlags = widget.destinations.map((e) => e.isSearch).toList();
    final badgeCounts = widget.destinations.map((e) => e.badgeCount).toList();

    if (_lastLabels?.join('|') != labels.join('|') ||
        _lastSymbols?.join('|') != symbols.join('|') ||
        _lastSelectedSymbols?.join('|') != selectedSymbols.join('|') ||
        _lastAssetIcons?.join('|') != assetIcons.join('|') ||
        _lastSelectedAssetIcons?.join('|') != selectedAssetIcons.join('|') ||
        _lastFileIcons?.join('|') != fileIcons.join('|') ||
        _lastSelectedFileIcons?.join('|') != selectedFileIcons.join('|') ||
        _lastNetworkIcons?.join('|') != networkIcons.join('|') ||
        _lastSelectedNetworkIcons?.join('|') !=
            selectedNetworkIcons.join('|')) {
      _lastLabels = labels;
      _lastSymbols = symbols;
      _lastSelectedSymbols = selectedSymbols;
      _lastAssetIcons = assetIcons;
      _lastSelectedAssetIcons = selectedAssetIcons;
      _lastFileIcons = fileIcons;
      _lastSelectedFileIcons = selectedFileIcons;
      _lastNetworkIcons = networkIcons;
      _lastSelectedNetworkIcons = selectedNetworkIcons;
      await _invoke(ch, 'setItems', {
        'labels': labels,
        'sfSymbols': symbols,
        'selectedSfSymbols': selectedSymbols,
        'assetIcons': assetIcons,
        'selectedAssetIcons': selectedAssetIcons,
        'fileIcons': fileIcons,
        'selectedFileIcons': selectedFileIcons,
        'networkIcons': networkIcons,
        'selectedNetworkIcons': selectedNetworkIcons,
        'searchFlags': searchFlags,
        'badgeCounts': badgeCounts,
        'badgeTexts': _mapBadgeTexts(),
        'badgeColors': _mapBadgeColors(),
        'badgeTextColors': _mapBadgeTextColors(),
        'selectedIndex': widget.selectedIndex,
      });
      _requestIntrinsicSize();
    }

    // Badge update (count + text + colors). Re-push when any badge input changes.
    final currentBadgeCounts = widget.destinations
        .map((e) => e.badgeCount)
        .toList();
    final currentBadgeTexts = _mapBadgeTexts();
    final currentBadgeColors = _mapBadgeColors();
    final currentBadgeTextColors = _mapBadgeTextColors();
    if (_lastBadgeCounts?.join('|') != currentBadgeCounts.join('|') ||
        _lastBadgeTexts?.join('|') != currentBadgeTexts.join('|') ||
        _lastBadgeColors?.join('|') != currentBadgeColors.join('|') ||
        _lastBadgeTextColors?.join('|') != currentBadgeTextColors.join('|')) {
      _lastBadgeCounts = currentBadgeCounts;
      _lastBadgeTexts = currentBadgeTexts;
      _lastBadgeColors = currentBadgeColors;
      _lastBadgeTextColors = currentBadgeTextColors;
      await _invoke(ch, 'setBadgeCounts', {
        'badgeCounts': currentBadgeCounts,
        'badgeTexts': currentBadgeTexts,
        'badgeColors': currentBadgeColors,
        'badgeTextColors': currentBadgeTextColors,
      });
    }

    // Minimize behavior update
    if (_lastMinimizeBehavior != widget.minimizeBehavior) {
      _lastMinimizeBehavior = widget.minimizeBehavior;
      await _invoke(ch, 'setMinimizeBehavior', {
        'behavior': widget.minimizeBehavior.index,
      });
    }

    // Hidden state update
    await _syncHiddenIfNeeded();

    // Blur state update
    if (_lastEnableBlur != widget.enableBlur) {
      _lastEnableBlur = widget.enableBlur;
      await _invoke(ch, 'setEnableBlur', {'enableBlur': widget.enableBlur});
    }
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      _lastIsDark = isDark;
      await _invoke(ch, 'setBrightness', {'isDark': isDark});
    }
  }

  Future<void> _syncDirectionalityIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isRtl = _isRtl;
    if (_lastIsRtl != isRtl) {
      _lastIsRtl = isRtl;
      await _invoke(ch, 'setDirectionality', {'isRtl': isRtl});
    }
  }

  void _cacheItems() {
    _lastLabels = widget.destinations.map((e) => e.label).toList();
    _lastSymbols = _mapSymbols();
    _lastSelectedSymbols = _mapSelectedSymbols();
    _lastAssetIcons = _mapAssetIcons();
    _lastSelectedAssetIcons = _mapSelectedAssetIcons();
    _lastFileIcons = _mapFileIcons();
    _lastSelectedFileIcons = _mapSelectedFileIcons();
    _lastNetworkIcons = _mapNetworkIcons();
    _lastSelectedNetworkIcons = _mapSelectedNetworkIcons();
    _lastBadgeCounts = widget.destinations.map((e) => e.badgeCount).toList();
    _lastBadgeTexts = _mapBadgeTexts();
    _lastBadgeColors = _mapBadgeColors();
    _lastBadgeTextColors = _mapBadgeTextColors();
  }

  Future<void> _syncHiddenIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final hidden = widget.hidden;
    if (_lastHidden == hidden) return;
    _lastHidden = hidden;
    await _invoke(ch, 'setHidden', {'hidden': hidden});
  }

  Future<void> _requestIntrinsicSize() async {
    if (widget.height != null) return;
    final ch = _channel;
    if (ch == null) return;
    try {
      final size = await _invoke<Map>(ch, 'getIntrinsicSize');
      final h = (size?['height'] as num?)?.toDouble();
      if (!mounted || h == null || h <= 0 || h == _intrinsicHeight) return;
      setState(() => _intrinsicHeight = h);
    } catch (_) {}
  }
}
