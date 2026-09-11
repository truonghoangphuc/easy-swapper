/// Google's User Messaging Platform, which is how ads stay legal in the EEA
/// and the UK.
///
/// Serving personalised ads to a user there without a certified consent
/// message breaches both GDPR and Google's own publisher policy, and AdMob will
/// stop serving rather than take the risk. Everywhere else UMP resolves to
/// "no consent needed" immediately and costs a round trip at startup.
///
/// The flow Google documents, and the one implemented here:
///
///   1. Ask UMP whether anything is required, for this user, in this region.
///   2. If a form is required, load and show it.
///   3. Only then request ads, and only if [canRequestAds] came back true.
///
/// Step 3 is the one that matters. Initialising the Mobile Ads SDK is always
/// fine; *requesting an ad* before consent is resolved is the violation.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class ConsentService {
  static bool _resolved = false;
  static bool _canRequestAds = false;
  static bool _privacyOptionsRequired = false;

  /// True once [gather] has finished, however it finished.
  static bool get isResolved => _resolved;

  /// Whether an ad may be requested at all.
  ///
  /// False until [gather] completes. Outside a consent region UMP reports true
  /// almost immediately; inside one it stays false until the user answers.
  static bool get canRequestAds => _canRequestAds;

  /// Whether this user must be offered a way to change their choice later.
  ///
  /// Required in consent regions, and the reason [showPrivacyOptions] exists.
  static bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// Only Android and iOS have the UMP SDK behind them.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Runs the consent flow. Safe to call more than once.
  ///
  /// Never throws and never blocks the game: a UMP failure leaves
  /// [canRequestAds] false, which costs the banner, not the session.
  static Future<void> gather() async {
    if (_resolved) return;
    if (!isSupported) {
      // Nothing to ask on desktop or web, and nothing to serve either.
      _resolved = true;
      return;
    }

    try {
      await _requestUpdate();
      await _showFormIfRequired();
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      _privacyOptionsRequired =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
              PrivacyOptionsRequirementStatus.required;
    } on Object catch (e) {
      debugPrint('ConsentService: consent flow failed, no ads: $e');
      _canRequestAds = false;
    } finally {
      _resolved = true;
    }
  }

  /// Wraps the callback-based update call in a future.
  ///
  /// Runs inside a guarded zone, and that is not belt-and-braces. The plugin's
  /// `requestConsentInfoUpdate` hands its platform-channel future to nobody:
  /// if the channel is missing or misbehaves, the error is never awaited and
  /// escapes every `try` this code could write - the same trap
  /// `MobileAds.instance` sets. A zone is the only thing that catches it, and
  /// without one a single UMP hiccup becomes an unhandled async error in an
  /// app that has otherwise handled it fine.
  static Future<void> _requestUpdate() {
    final done = Completer<void>();

    runZonedGuarded(
      () {
        ConsentInformation.instance.requestConsentInfoUpdate(
          ConsentRequestParameters(),
          () {
            if (!done.isCompleted) done.complete();
          },
          (FormError error) {
            debugPrint('ConsentService: update failed: ${error.message}');
            // Completed, not failed: the outer call still reads canRequestAds,
            // which is the authority on whether anything may be served.
            if (!done.isCompleted) done.complete();
          },
        );
      },
      (Object error, StackTrace stack) {
        debugPrint('ConsentService: update threw: $error');
        if (!done.isCompleted) done.complete();
      },
    );

    return done.future.timeout(
      // UMP reaches the network. If it hangs, the game must not hang with it.
      const Duration(seconds: 10),
      onTimeout: () => debugPrint('ConsentService: update timed out'),
    );
  }

  static Future<void> _showFormIfRequired() async {
    final done = Completer<void>();
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (error != null) {
          debugPrint(
            'ConsentService: form dismissed with error: ${error.message}',
          );
        }
        if (!done.isCompleted) done.complete();
      });
    } on Object catch (e) {
      debugPrint('ConsentService: could not show form: $e');
      if (!done.isCompleted) done.complete();
    }
    await done.future;
  }

  /// Reopens the consent form so a user can change their mind.
  ///
  /// Required by UMP in consent regions; a no-op elsewhere.
  static Future<void> showPrivacyOptions() async {
    if (!isSupported || !_privacyOptionsRequired) return;
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) {
          debugPrint('ConsentService: privacy form error: ${error.message}');
        }
      });
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } on Object catch (e) {
      debugPrint('ConsentService: could not show privacy options: $e');
    }
  }

  /// Test seam: forgets the resolved state so a test can run the flow again.
  @visibleForTesting
  static void resetForTest() {
    _resolved = false;
    _canRequestAds = false;
    _privacyOptionsRequired = false;
  }
}
