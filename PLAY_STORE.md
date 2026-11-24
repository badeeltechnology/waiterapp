# Google Play: listing and release checklist

Package: `com.badeel.servepos.waiter` (new app, new Play listing) · Version 2.0.0 (versionCode 3) · targetSdk 35 · minSdk 23

The old sideloaded app (`com.servepos.servepos_waiter`) was never on Play. The new id lets a waiter keep both apps on one phone while outlets migrate. iOS bundle id is the same `com.badeel.servepos.waiter`.

## TODO before push notifications work (Firebase)

`android/app/google-services.json` is not in git: download it from your Firebase project and put it there. Without it, or if it has no client for this package, the build skips the google-services plugin (Gradle prints a warning), the app runs fully without Firebase, and Account > Notifications shows "Push alerts off" (guest calls are then polled every 10 s while the app is open, nothing rings when it is closed).

1. Firebase console, project `servepos-ad41b` > Project settings > Add app > Android, package `com.badeel.servepos.waiter`, nickname "ServePOS Waiter 2".
2. Register SHA-1 and SHA-256 of the **upload key**: `keytool -list -v -keystore android/app/upload-keystore.jks -alias upload` Current upload key:
   - SHA-1 `55:A2:0A:7A:F6:3A:13:DF:0A:71:E6:A3:C7:D7:22:AE:6E:29:3F:21`
   - SHA-256 `21:59:22:96:01:F0:1B:AD:F1:E8:F5:E7:BA:54:47:08:36:71:99:83:E3:83:99:14:F9:6B:3A:C0:63:8E:10:8E`
3. After the first upload to Play with App Signing on, copy the SHA-1/SHA-256 of the **app signing key** from Play Console > Test and release > App integrity and add them to the same Firebase app.
4. Download the new `google-services.json` (it will contain both old and new clients) and save it as `android/app/google-services.json` (git ignores it). Rebuild: the Gradle warning disappears and Account shows "Push alerts on".
5. On the server, make sure the FCM credentials used by `servepos` belong to project `servepos-ad41b`.


## Store listing

**App name:** ServePOS Waiter

**Short description (max 80):**
Take table orders, see the live floor and answer guest calls for ServePOS.

**Full description:**

ServePOS Waiter is the handheld companion to the ServePOS restaurant till. It is for staff of restaurants that run ServePOS; you need an account from your manager to use it.

- Live floor: every table at a glance, free, occupied (with running total, minutes seated and waiter) or reserved.
- Fast ordering: categories, search in English or Arabic, modifiers (milk, sauces, extras) with required options enforced, per-item notes and guest count.
- Each table keeps its own draft, so walking between tables never mixes orders.
- Add a new round to a table that is already eating; the items already sent stay visible.
- Works through Wi-Fi drops: orders made offline wait on the phone, clearly marked "Waiting to send", and go out automatically when the connection returns. Nothing is shown as sent until the till confirms it.
- Guest calls ring loudly, even when the app is closed. Tap "I'm going" so colleagues know it is handled.
- Order status from the till and kitchen: Pending, Accepted, In Kitchen, Ready, Served.
- Secure: personal sign-in per waiter, fingerprint unlock, sign out lost phones from the app. Full Arabic interface.

**Category:** Business · **Tags:** restaurant, POS, waiter, ordering
**Contact email:** (Badeel support email) · **Privacy policy URL:** host `PRIVACY.md` as a web page (for example on badeel website) and paste the URL.

## Screenshots required

Phone screenshots, 1080x2340 (renderer output in `/home/claude/work/out/waiter_screens`, regenerate with `SCREENSHOT_DIR=... flutter test test/screenshots_test.dart`). Upload at least 4, recommended order:
1. Floor (02_floor.png)
2. Take order (03_take_order.png)
3. Modifiers (04_modifiers.png)
4. Review with sent and new rounds (05_review_sent_and_new.png)
5. Guest calls (07_calls.png)
6. Arabic (09_take_order_arabic.png)

Also needed: a 512x512 app icon (current `assets/images/app_icon.png` scaled) and a 1024x500 feature graphic (not made yet).

## Data safety form answers

- Does the app collect or share user data? **Yes, collects.** Shared with third parties: **No** (Firebase Cloud Messaging is a service provider, which Play does not count as sharing).
- Is all data encrypted in transit? **Yes** (HTTPS only in release builds).
- Can users request deletion? **Yes** (sign out deletes local data; server data via the restaurant / Badeel).
- Data types collected:
  - Personal info, **Email address / User IDs**: collected, required, purpose *App functionality, Account management*.
  - App activity, **Other user-generated content** (orders, notes): collected, required, *App functionality*.
  - Device or other IDs, **Device or other IDs** (app-generated device ID, FCM token): collected, required, *App functionality, Fraud prevention / security*.
  - Not collected: location, financial info, health, messages, photos, audio, files, calendar, contacts, web history, diagnostics, ads ID.
- Biometric data: none (Android handles fingerprints; the app only gets yes/no).

## App content declarations

- Ads: **No ads**.
- Target audience: **18+**, not designed for children.
- App access: **All functionality is restricted**. Provide a demo server URL, username and password for the reviewer (create a reviewer waiter user on a demo site with one POS profile and some tables).
- News app: No. Government app: No. Financial features: None. Health: No.
- **Full-screen intent (Android 14+)**: the manifest declares `USE_FULL_SCREEN_INTENT` so guest calls can take over the screen like an alarm. Play only auto-grants it to calling/alarm apps. Declare it in Play Console (App content > Full-screen intent) with the justification "Guest call alerts for restaurant staff, time-critical like an alarm". If Play refuses, remove the permission line from `AndroidManifest.xml`; calls still arrive as loud heads-up notifications.
- Foreground service: none. Exact alarms: none.

## Release steps (owner)

1. **Signing.** Use the existing `android/app/upload-keystore.jks` as the Play **upload key**, with **Play App Signing enabled** (Google holds the app signing key). Release signing reads `android/key.properties` (not in git; see `android/key.properties.example`). Back up the keystore and its passwords outside the repo; losing them means a key reset request to Google.
2. **Firebase.** Do the TODO above (new Android app, SHA fingerprints of the upload key and the Play app-signing key, new `google-services.json`).
3. **Server.** Deploy the `servepos` backend with WAITER_API_V2 (`servepos.api.mobile.*`), create a User with role ServePOS Waiter for each waiter and link it on their ServePOS Waiter record. Configure the FCM server credentials on the server so pushes go out.
4. **Build:** `flutter build appbundle --release` gives `build/app/outputs/bundle/release/app-release.aab`. Upload to Internal testing first.
5. **Privacy policy URL** (above) and **Data safety** form (above).
6. **Internal test** on 2 to 3 real phones: sign in, fingerprint, take an order with Wi-Fi off and back on, guest call with the app closed and the phone locked, and check the alarm sound volume.
7. Promote to Production.

Version bumps: change `version:` in `pubspec.yaml` (`2.0.1+4` etc.); the build number must always increase.
