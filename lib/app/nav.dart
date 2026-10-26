import 'package:flutter/widgets.dart';

/// Root navigator, so overlays above every screen can navigate.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The home tab on screen (0 floor, 1 orders, 2 calls, 3 account).
final currentHomeTab = ValueNotifier<int>(0);

/// Ask the home shell to switch tab (it pops pushed screens first).
final homeTabRequest = ValueNotifier<int?>(null);

void goHomeTab(int tab) {
  homeTabRequest.value = null;
  homeTabRequest.value = tab;
}
