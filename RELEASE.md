# Release checklist

Audited against the repository on 2026-09-06. Everything under **Blockers** is
something the current tree gets wrong, not a generic reminder — each one was
checked against the actual file named.

Store copy lives in [STORE.md](STORE.md); the player-facing rules are in
[HELP.md](HELP.md).

---

## Blockers — the build is not shippable until these are done

### 1. Release builds are signed with the debug key

`android/app/build.gradle.kts:37` reads:

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

Google Play rejects debug-signed uploads outright. There is no `key.properties`
and no keystore in the tree.

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties` (never commit it):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:/Users/you/upload-keystore.jks
```

Then wire it in `build.gradle.kts`, copying the pattern from
`easy-mathriss/android/app/build.gradle.kts` — it loads the properties file and
falls back to the debug config when absent, so a fresh clone still builds.

**Back the keystore up somewhere durable.** Lose it and you cannot ship an
update to the same listing, ever. (Play App Signing softens this — enrol.)

### 2. `.gitignore` does not exclude signing material

Add before creating any keystore:

```gitignore
android/key.properties
*.jks
*.keystore
ios/Runner/GoogleService-Info.plist
```

### 3. AdMob and leaderboard identifiers are placeholders

Both are wired and working, and **every identifier is a placeholder**. The app
runs and serves test ads as-is; it earns nothing and ranks nothing.

**AdMob** — replace in four places:

| Where | Currently |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | Google's demo app id |
| `ios/Runner/Info.plist` → `GADApplicationIdentifier` | Google's demo app id |
| Banner unit | demo, unless `--dart-define=admob_banner_android/ios` is passed |
| Rewarded unit | demo, unless `--dart-define=admob_rewarded_android/ios` is passed |

The app-id meta-data cannot simply be deleted — the Mobile Ads SDK aborts at
launch when it is missing or malformed. The *unit* ids are read from
`--dart-define` in release builds and fall back to the demo units otherwise, so
a debug build can never spend a real impression:

```bash
flutter build appbundle --release \
  --dart-define=admob_banner_android=ca-app-pub-XXXX/YYYY \
  --dart-define=admob_rewarded_android=ca-app-pub-XXXX/ZZZZ
```

easy-mathriss hardcodes its live unit ids in `lib/services/ad_service.dart`.
Do not copy that; they are in its git history forever.

**Leaderboards** — `lib/services/leaderboard_service.dart` ships with
`REPLACE_WITH_PLAY_LEADERBOARD_ID`, and `LeaderboardIds.configured` returns
false until it changes, so nothing is submitted. You need:

- **Play Games Services**: create the project in Play Console, add a
  leaderboard, take the `CgkI…` id, and put the numeric project id in
  `android/app/src/main/res/values/strings.xml` (`games_app_id`, currently
  `000000000000`). Add your tester accounts, or sign-in fails for everyone
  including you.
- **Game Center**: enable the capability on the App ID *and* in Xcode
  (Runner → Signing & Capabilities → + Game Center), then create a leaderboard
  in App Store Connect and use its id.

Pass both at build time:

```bash
--dart-define=leaderboard_android=CgkI... --dart-define=leaderboard_ios=easy_swapper_high_score
```

### 4. The privacy answers are no longer "nothing collected"

This changed the moment ads and Play Games went in, and it is the item most
likely to get the listing pulled.

- **Google Play Data safety**: AdMob collects the advertising ID and device
  information; Play Games collects a player id. Declare *Device or other IDs*
  as collected and shared, purpose "Advertising or marketing". Also tick the
  separate **contains ads** declaration.
- **App Store privacy**: declare *Identifiers* and *Usage Data*, used for
  Third-Party Advertising, linked to the user. Apple's questionnaire covers what
  your SDKs do, not only your own code.
- **ATT**: `NSUserTrackingUsageDescription` is set in `Info.plist`. If you want
  personalised ads on iOS you must also call
  `AppTrackingTransparency.requestTrackingAuthorization` before requesting the
  first ad — without the prompt, iOS returns a zeroed IDFA and fill rates fall.
- **Privacy policy URL** is now genuinely required by both stores, and it has to
  mention Google AdMob by name.
- **Do not target children.** Default AdMob configuration is not Families- or
  COPPA-compliant. See the note in [STORE.md](STORE.md).

### 5. No app icon

`assets/images/` is empty, `flutter_launcher_icons` is a dev dependency with
**no configuration block** in `pubspec.yaml`, and Android still points at the
stock `@mipmap/ic_launcher`.

Produce a 1024×1024 PNG at `assets/images/icon.png`, then add:

```yaml
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/images/icon.png"
  adaptive_icon_background: "#0A0E16"
  adaptive_icon_foreground: "assets/images/icon_foreground.png"
  remove_alpha_ios: true
```

```bash
dart run flutter_launcher_icons
```

iOS rejects icons with an alpha channel — `remove_alpha_ios` handles it.

### 6. Identifiers are inconsistent and one is ugly

| Where | Current | Problem |
| --- | --- | --- |
| `android/app/build.gradle.kts` | `com.easyindie.easy_swapper` | Underscore in a package name |
| `ios/Runner.xcodeproj` | `com.easyindie.easySwapper` | Mixed case, differs from Android |

**An application ID cannot be changed after the first publish.** Settle on
`com.easyindie.easyswapper` for both now. Change `applicationId` *and*
`namespace` on Android, and `PRODUCT_BUNDLE_IDENTIFIER` in all three Xcode
configurations.

### 7. Version is still a pre-release number

`pubspec.yaml:4` is `0.1.0+1`. Ship as `1.0.0+1`. The build number after `+`
must increase on every upload to either store, forever.

---

## Should do before the first submission

- **Remove the QA switches from release paths.** `--dart-define=autoplay=true`
  and `bombpercent` are harmless when unset, but confirm no CI job passes them.
- **Level select and progress persistence are not built.** Twenty levels exist
  in `core/levels/level_data.dart` and only endless mode is reachable. Either
  wire the level select or describe the game as endless-only in the listing —
  the current [STORE.md](STORE.md) copy is written for endless.
- **Decide on orientation.** The board is square and the layout letterboxes, but
  nothing locks rotation. Portrait-only is the usual choice for this genre.
- **Test on a low-end device.** Every brick paints nine gradients per frame,
  cached per colour. It is smooth on desktop; verify on a cheap Android phone.
- **`flutter build apk --analyze-size`** to check the download footprint. The
  ads and games-services SDKs add several megabytes.
- **The rewarded ad is implemented but not wired to anything.**
  `AdService.showRewardedAd` works and grants the reward even when no fill is
  available; what it should *give* is a game-design decision, not a technical
  one. The obvious hook is a second chance at a deadlock, since that is the only
  moment the player loses something. easy-mathriss spends its rewarded ads on
  extra hold slots, which this game has no equivalent of.
- **Ad consent (UMP) is not implemented.** Serving personalised ads to EEA or UK
  users requires a Google-certified consent message. Either add the UMP SDK or
  configure non-personalised ads only.

---

## Already dealt with

Kept here so these are not re-investigated:

- **Fonts are bundled, not fetched.** Baloo 2 and Sour Gummy live in
  `assets/fonts/` and are declared in `pubspec.yaml`; `google_fonts` is gone.
  This was a real bug, not a nicety: a release Android build has no `INTERNET`
  permission by default, so the runtime fetch never completed and both faces
  fell back to the system font. Only the OFL licence text remains outstanding —
  see `assets/fonts/README.md`.
- **`INTERNET` and `AD_ID` permissions** are declared, which ads and Play Games
  both need.
- **The app name** reads *Easy Swapper* in the Android manifest, `CFBundleName`,
  `web/manifest.json` and `web/index.html`.
- **`ITSAppUsesNonExemptEncryption`** is set to false, so iOS uploads skip the
  export-compliance question.
- **Everything degrades on unsupported platforms.** Ads and leaderboards are
  Android/iOS only; on Windows and web the banner collapses to zero height and
  the leaderboard button is not rendered at all. Verified on the Windows build.

---

## Google Play

- [ ] Play Console developer account (one-off 25 USD), identity verified —
      allow days for verification
- [ ] Enrol in **Play App Signing**
- [ ] `flutter build appbundle --release` → `build/app/outputs/bundle/release/`
- [ ] `targetSdk` must meet Play's current floor; it inherits from the Flutter
      SDK today, so pin it explicitly if a submission is rejected
- [ ] Store listing: title (30 chars), short description (80), full
      description (4000) — see [STORE.md](STORE.md)
- [ ] Graphics: 512×512 icon, 1024×500 feature graphic, 2–8 phone screenshots,
      plus 7" and 10" tablet screenshots if you declare tablet support
- [ ] Content rating questionnaire (this game rates **Everyone / PEGI 3**)
- [ ] Data safety form — **currently: no data collected, no data shared**. This
      stops being true the moment leaderboards, ads or analytics are added.
- [ ] Privacy policy URL — required even when collecting nothing
- [ ] Target audience and ads declarations (no ads today)
- [ ] Internal testing track first, then closed, then production

## Apple App Store

- [ ] Apple Developer Program (99 USD/year)
- [ ] App ID and provisioning via Xcode automatic signing
- [ ] Deployment target is iOS 13.0 (`project.pbxproj`) — fine, and above
      Apple's current minimum
- [ ] `flutter build ipa --release`, upload with Transporter or Xcode
- [ ] App Store Connect: name (30 chars), subtitle (30), promotional text (170),
      description (4000), keywords (100) — see [STORE.md](STORE.md)
- [ ] Screenshots for 6.7" and 6.5" iPhone; iPad if you claim iPad support
- [ ] App Privacy answers — **no data collected**, provided the fonts are
      bundled (blocker 3). Left as-is, the app contacts Google's font CDN and
      that has to be disclosed.
- [ ] Age rating (4+)
- [ ] Export compliance: no encryption beyond OS-standard — add
      `ITSAppUsesNonExemptEncryption = false` to `Info.plist` to skip the
      per-build prompt
- [ ] TestFlight build before submitting for review

## Ship-day sanity pass

```bash
flutter analyze              # expect: no issues
flutter test                 # expect: 159 passing
dart run tool/tune_weights.dart playout   # difficulty has not regressed
flutter build appbundle --release
flutter build ipa --release
```

Install the release artifact on a real device and check:

- **In aeroplane mode**: fonts render, sound plays, a deadlock reset behaves,
  and the banner slot collapses instead of leaving a grey bar.
- **Online**: the banner fills, and it sits below the board rather than over it.
- **Leaderboard**: the button appears, sign-in prompts once, and a finished run
  shows up in the ranking.

The fonts are the one thing aeroplane mode used to break, and it is worth
re-checking after any dependency change: they are now bundled in
`assets/fonts/`, not fetched. See `assets/fonts/README.md` — the OFL licence
text still needs to be added alongside them, which is the last outstanding
licensing obligation.
