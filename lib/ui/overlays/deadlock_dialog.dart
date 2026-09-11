/// Dialog shown when the board deadlocks in Endless mode.
///
/// Offers the player a chance to watch a rewarded ad and keep their score,
/// or decline and take the normal score-wipe reset.
library;

import 'package:flutter/material.dart';

import '../../game/swapper_game.dart';
import '../../services/ad_service.dart';

class DeadlockDialog extends StatefulWidget {
  const DeadlockDialog({required this.game, super.key});

  final SwapperGame game;

  @override
  State<DeadlockDialog> createState() => _DeadlockDialogState();
}

class _DeadlockDialogState extends State<DeadlockDialog> {
  bool _loading = false;

  void _watchAd() {
    setState(() => _loading = true);
    bool rewarded = false;
    AdService.showRewardedAd(
      onReward: () {
        rewarded = true;
        // Ad was fully watched — shuffle the board, score kept.
        widget.game.resolveDeadlock(shuffle: true);
        if (mounted) Navigator.of(context).pop();
      },
      onDismissed: () {
        // Always called after reward (or on failure).
        if (!rewarded && mounted) setState(() => _loading = false);
      },
    );
  }

  void _decline() {
    widget.game.resolveDeadlock(shuffle: false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasAd = AdService.isSupported && AdService.hasRewardedAd;

    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(120),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              const Text('😅', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),

              // Title
              const Text(
                'No Moves Left!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Body
              Text(
                hasAd
                    ? 'Watch a short ad to shuffle\nthe board and keep your score!'
                    : 'The board will be shuffled\nbut your score will reset.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),

              // Watch Ad button
              if (hasAd)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _watchAd,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_circle_fill, size: 20),
                    label: Text(_loading ? 'Loading…' : 'Watch Ad → Keep Score'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              if (hasAd) const SizedBox(height: 10),

              // Decline / Continue without ad
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : _decline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    hasAd ? 'No Thanks (Reset Score)' : 'Continue',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
