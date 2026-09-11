/// A widget that cross-fades between game backgrounds when they rotate.
library;

import 'package:flutter/material.dart';

import '../../services/background_service.dart';

/// Wraps [child] in a full-screen background that smoothly cross-fades to the
/// next image whenever [service] notifies a change.
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({
    required this.service,
    required this.child,
    super.key,
  });

  final BackgroundService service;
  final Widget child;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> {
  /// The asset path currently fading OUT (previous background).
  String? _outgoing;

  /// The asset path currently fading IN (current background).
  late String _incoming;

  @override
  void initState() {
    super.initState();
    _incoming = widget.service.current;
    widget.service.addListener(_onBackgroundChanged);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onBackgroundChanged);
    super.dispose();
  }

  void _onBackgroundChanged() {
    setState(() {
      _outgoing = _incoming;
      _incoming = widget.service.current;
    });
    // Clear the outgoing layer once the cross-fade completes.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _outgoing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Outgoing background fades out.
        if (_outgoing != null)
          AnimatedOpacity(
            key: ValueKey('out-$_outgoing'),
            opacity: 0,
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
            child: _BgImage(path: _outgoing!),
          ),

        // Incoming background fades in.
        AnimatedOpacity(
          key: ValueKey('in-$_incoming'),
          opacity: 1,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
          child: _BgImage(path: _incoming),
        ),

        // Game content sits on top.
        widget.child,
      ],
    );
  }
}

class _BgImage extends StatelessWidget {
  const _BgImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
