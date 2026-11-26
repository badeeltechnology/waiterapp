# ServePOS Waiter

Flutter app (Android first) for waiters of restaurants running ServePOS on ERPNext. Talks to the server contract in `WAITER_API_V2.md` (`servepos.api.mobile.*`).

## Download

[**Download the APK for Android**](https://github.com/badeeltechnology/waiterapp/releases/latest/download/ServePOS-Waiter.apk) (Android 7 or later)

On the phone, open the file and allow installing from this source when Android asks. Sign in with the server address, username and password a manager creates in the Serve POS manager app (**Waiters** › **Create login**). The desktop POS for the counter is in the [Serve POS Desktop](https://github.com/badeeltechnology/servepos-desktop#download) repository.

## Layout

```
lib/
  main.dart            production wiring
  app/                 services (dependency wiring), app root + auth gate
  core/                api client + error mapping, typed API, secure storage,
                       models, theme (Nami), i18n (EN/AR), alerts, push, platform
  features/
    auth/              server URL, login, lock screen, outlet picker, SessionController
    floor/             live floor
    order/             take order, modifier sheet, per-table carts, outbox, menu cache
    orders/            orders list, detail, outbox sheet
    calls/             guest calls
    settings/          account screen, AppSettings
    home/              bottom navigation shell + offline/outbox banners
  widgets/             shared UI pieces
test/                  unit + widget tests, screenshot renderer
```

State: `provider` with `ChangeNotifier` controllers, all built in `AppServices` (tests build it with fakes from `test/support/fakes.dart`).

## Commands

```
flutter pub get
flutter analyze
flutter test
SCREENSHOT_DIR=/tmp/shots flutter test test/screenshots_test.dart   # PNGs of the main screens
flutter build apk --release        # or: flutter build appbundle --release
```

Release signing reads `android/key.properties` (copy `android/key.properties.example`). Without it the release build is signed with the debug key and Gradle prints a warning.

See `PLAY_STORE.md` for the listing, data-safety answers and release steps, and `PRIVACY.md` for the privacy policy.

## Licence

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).
