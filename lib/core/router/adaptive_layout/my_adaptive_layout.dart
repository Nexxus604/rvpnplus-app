import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/features/chat/widget/chat_bubble.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/features/stats/widget/side_bar_stats_overview.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({
    super.key,
    required this.navigationShell,
    required this.isMobileBreakpoint,
    required this.showProfilesAction,
  });
  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;
  final bool showProfilesAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // focus switch management
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();
    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint ? KeyboardConst.verticalArrows : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          // focus node does not change => true.
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex)]
                  ?.requestFocus();
            }
          }
        }
        return true;
      }

      HardwareKeyboard.instance.addHandler(handler);
      return () {
        HardwareKeyboard.instance.removeHandler(handler);
      };
    }, [isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex]);
    return Material(
      child: Scaffold(
        body: isMobileBreakpoint
            ? navigationShell
            : Row(
                children: [
                  FocusScope(
                    node: navScopeNode,
                    child: NavigationRail(
                      extended: Breakpoint(context).isDesktop(),
                      destinations: _navRailDests(_actions(t, showProfilesAction, isMobileBreakpoint)),
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: (index) => _onTap(context, index),
                      trailing: Breakpoint(context).isDesktop()
                          ? const Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(width: 220, child: SideBarStatsOverview()),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Expanded(child: navigationShell),
                ],
              ),
        bottomNavigationBar: isMobileBreakpoint
            ? LayoutBuilder(
                builder: (context, constraints) {
                  // 3 slots; the rocket bubble floats over the 3rd (right) one.
                  // NB: do NOT force a fixed height — NavigationBar adds the
                  // system-navbar safe-area itself; constraining it clips the
                  // labels. Let the Stack size to the NavigationBar.
                  final slotCenter = constraints.maxWidth * 5 / 6;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FocusScope(
                        node: navScopeNode,
                        child: NavigationBar(
                          selectedIndex:
                              navigationShell.currentIndex <= 1 ? navigationShell.currentIndex : 0,
                          destinations: [
                            NavigationDestination(
                              icon: const Icon(Icons.power_settings_new_rounded),
                              label: t.pages.home.title,
                            ),
                            NavigationDestination(
                              icon: const Icon(Icons.settings_rounded),
                              label: t.pages.settings.title,
                            ),
                            // Placeholder — the floating rocket bubble sits
                            // over this slot. No label (the rocket speaks for
                            // itself).
                            const NavigationDestination(
                              icon: SizedBox(width: 36, height: 26),
                              label: '',
                            ),
                          ],
                          onDestinationSelected: (index) => _onTap(context, index),
                        ),
                      ),
                      // Big pulsing support rocket — floats FAB-style above
                      // the 3rd slot so it stands out; the "Поддержка" label
                      // stays visible under it. Clip.none lets it overflow.
                      Positioned(
                        left: slotCenter - 42,
                        top: -20,
                        child: RocketMark(
                          size: 84,
                          onTap: () => GoRouter.of(context).push('/chat'),
                        ),
                      ),
                    ],
                  );
                },
              )
            : null,
      ),
    );
  }

  // shell route action onTap
  void _onTap(BuildContext context, int index) {
    // On mobile the 3rd item is the AI assistant — push the chat route
    // instead of switching a shell branch (Home=0, Settings=1, AI=2).
    if (isMobileBreakpoint && index == 2) {
      GoRouter.of(context).push('/chat');
      return;
    }
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  List<ShellRouteAction> _actions(Translations t, bool showProfilesAction, bool isMobileBreakpoint) => [
    ShellRouteAction(Icons.power_settings_new_rounded, t.pages.home.title),
    if (showProfilesAction && !isMobileBreakpoint) ShellRouteAction(Icons.view_list_rounded, t.pages.profiles.title),
    ShellRouteAction(Icons.settings_rounded, t.pages.settings.title),
    if (!isMobileBreakpoint) ShellRouteAction(Icons.description_rounded, t.pages.logs.title),
    if (!isMobileBreakpoint) ShellRouteAction(Icons.info_rounded, t.pages.about.title),
  ];

  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}
