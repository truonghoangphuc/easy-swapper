# Easy Swapper — Publish Readiness Checklist

Audited against the live tree on 2026-09-11, and re-audited after the
"Should Do" items were implemented the same day.

---

## 🔴 Blockers — Must fix before any store submission

### 1. Android release build signed with the debug key
**File:** [`android/app/build.gradle.kts:37`](file:///Users/phuc/Development/Projects/flutter/easy-swapper/easy-swapper/android/app/build.gradle.kts#L37)

```kotlin
signingConfig = signingConfigs.getByName("debug")  // ← still debug
```

`android/key.properties` → **MISSING**. Google Play hard-rejects debug-signed uploads.

**Fix:**
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Create `android/key.properties`, wire it in `build.gradle.kts`. **Back up the keystore.**

---

### 2. `.gitignore` missing signing material entries

Current `.gitignore` does **not** exclude `android/key.properties`, `*.jks`, or `*.keystore`. Add these before creating any keystore or they risk being committed.

```gitignore
android/key.properties
*.jks
*.keystore
ios/Runner/GoogleService-Info.plist
```

---

### 3. AdMob IDs — **PARTIALLY DONE**

| Where | Status |
|---|---|
| Android `AndroidManifest.xml` app ID | ✅ Real ID: `ca-app-pub-5104291908556139~8410729598` |
| iOS `Info.plist` GADApplicationIdentifier | ✅ Real ID: `ca-app-pub-5104291908556139~1994329205` |
| Banner unit id (`--dart-define=admob_banner_android/ios`) | ⚠️ Falls back to demo unit unless passed at build time |
| Rewarded unit id (`--dart-define=admob_rewarded_android/ios`) | ⚠️ Falls back to demo unit unless passed at build time |

**Action:** Pass real unit IDs at build time:
```bash
flutter build appbundle --release \
  --dart-define=admob_banner_android=ca-app-pub-XXXX/YYYY \
  --dart-define=admob_banner_ios=ca-app-pub-XXXX/YYYY \
  --dart-define=admob_rewarded_android=ca-app-pub-XXXX/ZZZZ \
  --dart-define=admob_rewarded_ios=ca-app-pub-XXXX/ZZZZ
```

---

### 4. Leaderboard IDs are placeholders

| Where | Status |
|---|---|
| `android/app/src/main/res/values/strings.xml` `games_app_id` | 🔴 `000000000000` |
| Android leaderboard ID (`--dart-define=leaderboard_android`) | ⚠️ Empty → `LeaderboardIds.configured` is false, nothing submitted |
| iOS leaderboard ID (`--dart-define=leaderboard_ios`) | ⚠️ Empty → same |

**Action:** Create leaderboards in Play Console and App Store Connect, then pass IDs at build time.

---

### 5. Privacy declarations are out of date

The app now uses AdMob (advertising ID) and Play Games (player ID). Both stores require updated declarations:

- **Google Play Data Safety**: declare *Device or other IDs* as collected + shared, purpose "Advertising"; tick **contains ads**.
- **App Store Privacy**: declare *Identifiers* + *Usage Data* for Third-Party Advertising.
- **ATT prompt** (`AppTrackingTransparency`): required on iOS for personalised ads; `NSUserTrackingUsageDescription` is set in `Info.plist`, but the runtime call is not implemented.
- **Privacy policy URL** (required by both stores) — must mention Google AdMob by name.

---

### 6. App identifier mismatch

| Where | Current |
|---|---|
| Android `applicationId` / `namespace` | `com.easyindie.easy_swapper` (underscore) |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.easyindie.easySwapper` (mixed case) |

> [!CAUTION]
> Application ID **cannot be changed after first publish.** Settle on a single consistent ID (e.g. `com.easyindie.easyswapper`) for both platforms now.

---

### 7. Version is pre-release

[`pubspec.yaml:4`](file:///Users/phuc/Development/Projects/flutter/easy-swapper/easy-swapper/pubspec.yaml#L4): `version: 0.1.0+1`

Change to `1.0.0+1` before submission. The build number (`+1`) must increase on every upload forever.

---

## 🟡 Should Do Before First Submission

- **Test on a low-end Android device.** Not done — no device available here.
  Each brick paints nine gradients, cached per colour so only flashing and
  throbbing tiles rebuild them, and the solver runs ~112 board scans per settle
  in a few milliseconds on desktop. Neither has been measured on a cheap phone.
  This is the one item on the original list that cannot be closed from a
  workstation.
- **Fill in the font copyright lines.** `assets/fonts/OFL-Baloo2.txt` and
  `OFL-SourGummy.txt` now carry the verbatim SIL OFL 1.1 text, but the
  copyright line in each is a marked placeholder. It names real people and was
  deliberately not guessed — copy it from each family's own `OFL.txt` on Google
  Fonts. Everything else about the licensing obligation is satisfied.

### Implemented since the audit

| Item | What was done |
|---|---|
| Adaptive launcher icon | The square icon was generated but there was no `mipmap-anydpi-v26`, so Android 8+ letterboxed the logo into a white circle. Added `adaptive_icon_background` (`#0A0E16`), foreground and monochrome (Android 13 themed icons) with a 20% inset so the launcher's mask crops padding instead of artwork, and regenerated. |
| Portrait lock | `android:screenOrientation="portrait"`, `UISupportedInterfaceOrientations` reduced to portrait on both iPhone and iPad, plus `SystemChrome.setPreferredOrientations` in `main`. `UIRequiresFullScreen = true` was needed too: an iPad app that supports Slide Over and Split View must support every orientation, so opting out of multitasking is what *permits* the lock. |
| Ad consent (UMP) | New `lib/services/consent_service.dart`. Requests consent info, shows the form when required, and — the part that matters — **every ad request is now gated on `canRequestAds`**. Initialising the SDK early is fine; requesting an ad before UMP answers is the violation. A "Manage ad privacy choices" entry point appears in the help panel, but only when UMP says it is required. |
| Banner retry outlasts the form | The banner gave up after 5 attempts over 10s. In the EEA a consent form is on screen for as long as the player reads it, and `AdService.banner` returns null throughout. Budget raised, and retrying now stops early when consent is *resolved and refused* — a decline costs one attempt, not twenty. |

### Two claims in the original audit were already stale

- **Rewarded ad is wired.** `lib/ui/overlays/deadlock_dialog.dart:27` calls
  `AdService.showRewardedAd`, offering a board shuffle that keeps the score.
- **Level select is reachable.** `lib/main.dart` opens `LevelSelectScreen`
  unless a saved game is being resumed.

Both were listed as outstanding; neither was.

---

## ✅ Already Done

| Item | Detail |
|---|---|
| Fonts bundled | Baloo 2 & Sour Gummy in `assets/fonts/`, no runtime fetch |
| App name | "Easy Swapper" in AndroidManifest, CFBundleName, web manifest |
| `INTERNET` + `AD_ID` permissions | Declared in AndroidManifest |
| `ITSAppUsesNonExemptEncryption = false` | Set in `Info.plist` |
| AdMob app IDs | Real IDs in both platforms (see §3 above) |
| Icon image asset | `easy_swapper_logo.png` — 1024×1024 ✅ |
| `flutter_launcher_icons` config | Configured in `pubspec.yaml` ✅ (but not yet run) |
| Ad/leaderboard degrades on web/Windows | Banner collapses, leaderboard button hidden |
| Store copy written | See [STORE.md](file:///Users/phuc/Development/Projects/flutter/easy-swapper/easy-swapper/STORE.md) |
| Launcher icons | Generated for Android, iOS and web, with adaptive + monochrome variants |
| Portrait lock | Android manifest, Info.plist (incl. iPad), and `SystemChrome` |
| UMP consent | Implemented and gating every ad request |
| OFL licence body | Verbatim OFL 1.1 in `assets/fonts/` (copyright line still to fill) |
| Rewarded ad hooked up | Deadlock dialog offers a shuffle that keeps the score |
| Level select reachable | `main.dart` → `LevelSelectScreen` |
| Services bootstrapped in `main`, not in the game | Building a `SwapperGame` no longer reaches for the AdMob or UMP channels |
| HUD overflow on small screens | Fixed — two-row layout (score/moves row + icons row) |

---

## Ship-Day Commands

```bash
flutter analyze              # expect: no issues
flutter test                 # expect: all passing
flutter build appbundle --release \
  --dart-define=admob_banner_android=... \
  --dart-define=admob_banner_ios=... \
  --dart-define=admob_rewarded_android=... \
  --dart-define=admob_rewarded_ios=... \
  --dart-define=leaderboard_android=CgkI... \
  --dart-define=leaderboard_ios=easy_swapper_high_score
flutter build ipa --release [same --dart-defines]
```

Install release artifact on a real device and verify:
- **Aeroplane mode**: fonts render, sound plays, banner collapses (no grey bar)
- **Online**: banner fills, sits below board, leaderboard sign-in works
