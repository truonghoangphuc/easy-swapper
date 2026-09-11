# Easy Swapper — App Store & Play Store Submission Content

Everything needed to fill in App Store Connect and Google Play Console,
collected in the order each form actually asks for it. The marketing prose
lives in [STORE.md](STORE.md) — this file quotes the final values, adds the
fields STORE.md doesn't cover (privacy policy, data safety, content rating),
and flags what's missing outright rather than inventing it.

**Before using this file:** the seven 🔴 blockers in
[PUBLISH_CHECKLIST.md](PUBLISH_CHECKLIST.md) — signing key, ad unit IDs,
leaderboard IDs, bundle ID mismatch, version bump — are build/config problems,
not listing content, so they aren't repeated here. Fix those first; this file
can be prepared in parallel.

---

## App identity

| | Value |
|---|---|
| App name | Easy Swapper |
| Package name (Android) | `com.easyindie.easy_swapper` ⚠️ see below |
| Bundle ID (iOS) | `com.easyindie.easySwapper` ⚠️ see below |
| Version | `0.1.0+1` ⚠️ must become `1.0.0+1` before submission |
| Category | Games → Puzzle |
| Price | Free |

⚠️ **The Android and iOS identifiers don't match** (underscore vs. mixed
case), and an application ID **cannot change after first publish** on either
store. Pick one spelling — `com.easyindie.easyswapper` is the safe middle
ground — and set it on both platforms before the first upload. This is
[blocker #6](PUBLISH_CHECKLIST.md#6-app-identifier-mismatch); it belongs here
too because it's what you'll type into both consoles.

---

## Two things this repo cannot produce for you

Both stores **require a live URL** for these — a markdown file can hold the
text, but the text has to be hosted somewhere reachable before either form
will accept it.

1. **Privacy policy URL.** Draft below, ready to paste onto a page (GitHub
   Pages, a Google Site, anything static works). Google Play and Apple both
   demand this the moment an app requests any permission or shows ads — Easy
   Swapper does both.
2. **Support URL / contact email.** Apple requires a support URL on every
   listing; Play strongly expects one. Pick an email or a page and use it
   consistently across both stores — a support contact that doesn't exist yet
   is a common cause of app-review rejection on its own.

Everything else below can be pasted straight into the consoles once those two
exist.

---

## Google Play Console

### Store listing → Main store listing

| Field | Value | Limit |
|---|---|---|
| App name | `Easy Swapper` | 30 |
| Short description | `Swap the bricks to build real equations. Match three with actual arithmetic.` | 80 (76 used) |
| Full description | See [Long description](STORE.md#long-description-google-play-4000-max--this-is-1900) in STORE.md | 4000 (~1,900 used) |

### Store listing → Graphics

| Asset | Spec | Status |
|---|---|---|
| App icon | 512×512 PNG | ✅ generated from `easy_swapper_logo.png` |
| Feature graphic | 1024×500 | See [STORE.md § Feature graphic](STORE.md#feature-graphic--google-play-1024500) — not yet created |
| Phone screenshots | 2–8, min 320px, 16:9 or 9:16 | See [STORE.md § Screenshots](STORE.md#screenshots) — shot list ready, not yet captured |

### App content → Privacy policy
Paste the hosted URL from the draft below.

### App content → Ads
**Yes, this app contains ads.** (AdMob banner, and a rewarded ad for the
deadlock-shuffle option.)

### App content → Content rating (questionnaire answers)

| Question | Answer |
|---|---|
| Violence | None |
| Sexual content | None |
| Profanity | None |
| Controlled substances | None |
| User-generated content | None |
| Shares personal info with other users | No |
| Location sharing | No |
| Digital purchases | No |
| Unrestricted internet access | Yes (ads, leaderboard) |

Expected outcome: **PEGI 3 / Everyone**. The bomb and lightning effects are
cartoon particle bursts on a grid of numbers — not depicted violence.

### App content → Data safety

| Data type | Collected? | Shared? | Purpose |
|---|---|---|---|
| Device or other IDs (advertising ID) | Yes | Yes | Advertising, analytics |
| App activity (game progress, in-app actions) | Yes | No | App functionality (save/resume, leaderboard) |
| Account info (if signed into Play Games) | No — handled by Play Games directly | — | — |

Data is **encrypted in transit**. Users **cannot request deletion** through
the app itself (there's no account), but uninstalling removes all local data —
state that if Play's form asks.

### App content → Target audience and content
**Not** designed for children. AdMob is not configured for
`tagForChildDirectedTreatment`; leave the "Families" / "designed for children"
questions answered **No** unless that configuration work is done first
(re-tuning the whole ad and privacy stack).

### App content → Government apps / News / COVID-19
No, no, no — not applicable.

### Store settings
- Category: **Games**
- Tags: Puzzle, Word (if offered — Play sometimes buckets math puzzles there),
  Board
- Contact details: support email/URL (see above), no phone number required

---

## App Store Connect

### App Information

| Field | Value | Limit |
|---|---|---|
| Name | `Easy Swapper` | 30 |
| Subtitle | `Swap tiles, build equations` | 30 |
| Primary category | Games | — |
| Secondary category | Education (optional but fits — it's arithmetic practice with a game wrapped around it) | — |
| Content rights | Does not use third-party content requiring rights declarations | — |
| Age rating | 4+ (see questionnaire below) | — |

### Pricing and Availability
Free, available in all territories AdMob/Play Games support (default: all).

### Version information → Promotional text (170 max, editable anytime without review)

```
Every tile is a number or an operator. Swap two, and if the row adds up, it
detonates. Bombs clear a whole cross. One rule, endless boards, no timers.
```

### Version information → Description
Same body as [STORE.md § Long description](STORE.md#long-description-google-play-4000-max--this-is-1900).
Apple renders `•` bullets fine; lead with the first two paragraphs since the
description truncates after ~3 lines before "more."

### Version information → Keywords (100 max, comma-separated, no spaces)

```
math,maths,puzzle,match3,numbers,equation,arithmetic,brain,logic,swap,tiles,sums
```

79 characters used. Don't repeat "Easy Swapper" — Apple already indexes the
app name and subtitle separately. Do **not** include `noads` or `offline`;
neither is true once AdMob and the leaderboard are live, and a keyword that
contradicts the app's actual behavior is a rejection risk in review.

### Version information → Support URL / Marketing URL
Support URL: required, see above. Marketing URL: optional, skip if there's no
landing page.

### Version information → Screenshots
Same shot list as [STORE.md § Screenshots](STORE.md#screenshots) — 6 images,
captured at each required device size (6.7", 6.5", 5.5" for iPhone; largest
iPad size if the app supports iPad, which per
[PUBLISH_CHECKLIST.md](PUBLISH_CHECKLIST.md) it currently does with a portrait
lock). Not yet captured.

### App Privacy (the questionnaire, per data type)

| Data type | Collected | Linked to identity | Used for tracking |
|---|---|---|---|
| Identifiers (Device ID / IDFA) | Yes | No | Yes (personalized ads, pending consent) |
| Usage Data | Yes | No | Yes (advertising analytics) |
| Game Center player ID (if signed in) | Handled entirely by Apple's Game Center, not this app's own collection | — | — |

Because the app can track via IDFA for advertising, **App Tracking
Transparency (ATT)** applies. `NSUserTrackingUsageDescription` is already set
in `Info.plist`, but per
[PUBLISH_CHECKLIST.md item 5](PUBLISH_CHECKLIST.md#5-privacy-declarations-are-out-of-date)
the runtime `AppTrackingTransparency.requestTrackingAuthorization()` call is
**not yet implemented**. Apple review checks that the prompt actually fires
before ad requests go out — declaring tracking in the questionnaire without
the runtime prompt is an inconsistency that gets apps rejected.

### Age Rating questionnaire

| Question | Answer |
|---|---|
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Sexual content or nudity | None |
| Profanity or crude humor | None |
| Alcohol, tobacco, drugs | None |
| Mature/suggestive themes | None |
| Horror/fear themes | None |
| Gambling (simulated) | None |
| Contests | None |
| Unrestricted web access | No |
| Ads | Yes |

Expected outcome: **4+**.

### App Review Information
- Sign-in required: **No**
- Demo account: not applicable
- Notes for reviewer, suggested:
  ```
  No account or sign-in is required to play. Game Center and a banner/rewarded
  ad (Google AdMob) are optional and degrade gracefully if declined. The board
  is fully playable offline; only the ad and the leaderboard need a
  connection.
  ```

---

## Privacy policy — draft text

Host this at whatever URL goes into both consoles' privacy policy fields.
Written to match what the app actually does — no more, no less — since an
inaccurate policy is itself a compliance problem.

```markdown
# Privacy Policy — Easy Swapper

Last updated: [DATE]

Easy Swapper is developed by [DEVELOPER / COMPANY NAME]. This policy explains
what data the app collects and why.

## Data we collect

**Advertising identifiers.** Easy Swapper shows ads through Google AdMob.
AdMob may collect your device's advertising ID and usage data to serve and
measure ads, including personalized ads where you have given consent. Where
required (including the EEA and UK), a consent form is shown before any
personalized ad request, and you can change your choice at any time from the
in-game Help screen ("Manage ad privacy choices").

**Game progress.** Your score, level progress, and settings are stored
locally on your device so your game resumes where you left off. This data is
not sent to us.

**Leaderboard identity.** If you choose to sign in to Game Center (iOS) or
Play Games (Android), your score is submitted to that platform's leaderboard
service under the account you're signed into. This is entirely optional —
the game is fully playable without signing in — and is governed by Apple's or
Google's own privacy policy, not ours.

## Data we do not collect

We do not collect your name, email address, or any content you create. There
is no account system and no user-generated content.

## Third parties

- **Google AdMob** — ad serving and measurement. See Google's privacy policy
  at https://policies.google.com/privacy
- **Apple Game Center** / **Google Play Games** — optional leaderboard
  services, governed by Apple's or Google's respective privacy policies.

## Children

Easy Swapper is not directed at children and is not configured for
child-directed advertising. If you believe a child has provided us data in a
way that concerns you, contact us at [SUPPORT EMAIL].

## Your choices

- Ad personalization consent can be withdrawn at any time from the in-game
  Help screen, where available under your region's requirements.
- Leaderboard sign-in is optional; declining it does not affect gameplay.
- Uninstalling the app removes all locally stored progress.

## Contact

Questions about this policy: [SUPPORT EMAIL]
```

Fill in `[DATE]`, `[DEVELOPER / COMPANY NAME]`, and `[SUPPORT EMAIL]` before
publishing it, and update "Last updated" if the ad/leaderboard stack changes.

---

## Cross-check before submitting

- [ ] Privacy policy hosted at a live URL, pasted into both consoles
- [ ] Support URL or email set, consistent across both listings
- [ ] Bundle ID reconciled between Android and iOS ([blocker #6](PUBLISH_CHECKLIST.md#6-app-identifier-mismatch))
- [ ] Version bumped to `1.0.0+1` ([blocker #7](PUBLISH_CHECKLIST.md#7-version-is-pre-release))
- [ ] Real AdMob unit IDs and leaderboard IDs passed at build time ([blockers #3–4](PUBLISH_CHECKLIST.md#3-admob-ids--partially-done))
- [ ] Data Safety (Play) and App Privacy (Apple) questionnaires answered as above
- [ ] ATT runtime prompt implemented before declaring tracking on iOS
- [ ] Screenshots and feature graphic captured per [STORE.md § Screenshots](STORE.md#screenshots)
- [ ] `flutter analyze` clean, `flutter test` passing, release build signed with a real key
