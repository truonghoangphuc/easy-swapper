/// The AdMob banner slot.
///
/// Reserves no height until an ad actually loads. Reserving it up front leaves a
/// grey bar on every platform without ads - Windows, web - and a visible gap on
/// mobile whenever a fill fails.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_service.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  /// `AdService.init` runs in the background, so the first request can land
  /// before the SDK is up. A few retries cover that; after them, give up
  /// quietly rather than polling for the life of the session.
  static const int _maxAttempts = 5;
  static const Duration _retryDelay = Duration(seconds: 2);

  BannerAd? _ad;
  bool _loaded = false;
  int _attempts = 0;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void dispose() {
    // Must be cancelled: a pending retry outlives the widget, holds a closure
    // over `mounted`, and in a widget test shows up as a leaked timer.
    _retry?.cancel();
    super.dispose();
  }

  void _request() {
    if (!AdService.isSupported) return;

    final ad = AdService.banner(() {
      if (mounted) setState(() => _loaded = true);
    });
    if (ad != null) {
      _ad = ad;
      return;
    }

    if (++_attempts >= _maxAttempts) return;
    _retry = Timer(_retryDelay, () {
      if (mounted) _request();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
