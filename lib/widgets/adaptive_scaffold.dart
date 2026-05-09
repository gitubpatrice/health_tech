import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Navigation destination shared between BottomNavigationBar (compact) and
/// NavigationRail / NavigationDrawer (medium / expanded).
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Phone-and-tablet aware scaffold.
///
/// Layout:
/// - compact  (< 600 dp): bottom nav, single pane.
/// - medium   (< 840 dp): NavigationRail (compact) + single pane.
/// - expanded (>= 840 dp): NavigationRail (extended) + caller manages two-pane
///   layout in the body (the master-detail concern stays in feature widgets).
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    if (size == WindowSize.compact) {
      return Scaffold(
        appBar: AppBar(title: title, actions: actions),
        body: SafeArea(child: body),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = size == WindowSize.expanded;
    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: extended,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Master-detail container for tablet layouts. On compact, only [list] is
/// shown; on medium/expanded, [list] and [detail] are shown side by side.
class MasterDetailLayout extends StatelessWidget {
  const MasterDetailLayout({
    super.key,
    required this.list,
    required this.detail,
    this.listFlex = 2,
    this.detailFlex = 3,
  });

  final Widget list;
  final Widget detail;
  final int listFlex;
  final int detailFlex;

  @override
  Widget build(BuildContext context) {
    if (context.isCompact) return list;
    return Row(
      children: [
        Expanded(flex: listFlex, child: list),
        const VerticalDivider(width: 1),
        Expanded(flex: detailFlex, child: detail),
      ],
    );
  }
}
