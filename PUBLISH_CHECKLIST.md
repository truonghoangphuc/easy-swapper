# Easy Swapper — Publish Readiness Checklist

Audited against the live tree on 2026-09-11.

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

- **App icon is configured but not generated yet.** The logo exists at `assets/images/easy_swapper_logo.png` (1024×1024 RGBA ✅) and `flutter_launcher_icons` is configured in `pubspec.yaml` — but `dart run flutter_launcher_icons` has not been run yet (Android still points at default `@mipmap/ic_launcher`). Run it.
- **Portrait-only orientation not locked.** Common for this genre. Lock in `AndroidManifest.xml` and `Info.plist`.
- **Ad consent (UMP) not implemented.** EEA/UK users require a Google-certified consent message for personalised ads. Either add the UMP SDK or serve non-personalised ads only.
- **Rewarded ad not wired to gameplay.** `AdService.showRewardedAd` works but is never called. The natural hook is the deadlock dialog (offer a second chance in exchange for watching an ad).
- **Level select not reachable.** 20 levels exist in `core/levels/level_data.dart` but only endless mode is accessible from the UI. Either wire the level select screen or ensure store copy describes the game as endless-only (current [STORE.md](file:///Users/phuc/Development/Projects/flutter/easy-swapper/easy-swapper/STORE.md) is already written for endless).
- **Test on a low-end Android device.** Bricks paint nine gradients per frame; verify performance on a cheap phone.
- **OFL licence text** for bundled fonts (Baloo 2, Sour Gummy) still needs to be placed in `assets/fonts/` alongside the font files.

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
