import 'package:flutter/widgets.dart';

/// Single source of truth for layout breakpoints.
///
/// Following Material 3 window-size classes:
/// - compact (< 600 dp)  : phone portrait
/// - medium  (< 840 dp)  : phone landscape, tablet portrait
/// - expanded (>= 840 dp): tablet landscape, foldables, large
class Breakpoints {
  const Breakpoints._();

  static const double compactMax = 600;
  static const double mediumMax = 840;
}

enum WindowSize { compact, medium, expanded }

extension WindowSizeExtension on BuildContext {
  WindowSize get windowSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width < Breakpoints.compactMax) return WindowSize.compact;
    if (width < Breakpoints.mediumMax) return WindowSize.medium;
    return WindowSize.expanded;
  }

  bool get isCompact => windowSize == WindowSize.compact;
  bool get isExpanded => windowSize == WindowSize.expanded;
}
