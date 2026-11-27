import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_bottom_nav_bar.dart';

/// The main app frame: the current tab plus the floating bottom navigation.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<AppNavItem> tabs = [
    AppNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    AppNavItem(
      label: 'Requests',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
    ),
    AppNavItem(
      label: 'Wallet',
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
    ),
    AppNavItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  void _selectTab(int index) {
    // Tapping the current tab again returns it to its first screen.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onHome = navigationShell.currentIndex == 0;

    return PopScope<Object?>(
      // Android back on another tab returns to Home instead of closing the app.
      canPop: onHome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !onHome) _selectTab(0);
      },
      child: Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: AppBottomNavBar(
          items: tabs,
          currentIndex: navigationShell.currentIndex,
          onTap: _selectTab,
        ),
      ),
    );
  }
}

/// Keeps every tab alive (state and scroll position are preserved) and
/// fades in the selected tab.
class FadingTabContainer extends StatefulWidget {
  const FadingTabContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<FadingTabContainer> createState() => _FadingTabContainerState();
}

class _FadingTabContainerState extends State<FadingTabContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void didUpdateWidget(FadingTabContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: IndexedStack(
        index: widget.currentIndex,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            // Hidden tabs are excluded from tapping and screen readers.
            TickerMode(
              enabled: i == widget.currentIndex,
              child: ExcludeSemantics(
                excluding: i != widget.currentIndex,
                child: widget.children[i],
              ),
            ),
        ],
      ),
    );
  }
}
