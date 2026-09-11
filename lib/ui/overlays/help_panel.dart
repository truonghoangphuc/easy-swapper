/// The in-game rules screen.
///
/// Kept in sync with `HELP.md`, which is the longer version and the source for
/// the store listing. This one is trimmed to what a player needs mid-game.
library;

import 'package:flutter/material.dart';

import '../../services/consent_service.dart';
import '../theme/app_theme.dart';

class HelpPanel extends StatelessWidget {
  const HelpPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.boardBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gridLine, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'HOW TO PLAY',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textDim,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _Rule(
                            'Swap to make the maths work',
                            'Drag a brick into its neighbour, or tap one then '
                                'the other. The swap only goes through if it '
                                'completes a true equation. If it does not, '
                                'nothing moves and it costs you nothing.',
                          ),
                          _Rule(
                            'Digits side by side make one number',
                            '1, 9 and 9 in a row is one hundred and '
                                'ninety-nine. Long numbers are how the big '
                                'runs get built.',
                          ),
                          _Rule(
                            'Normal precedence, no brackets',
                            '1 + 2 x 3 is 7, not 9. Powers first, then multiply '
                                'and divide, then add and subtract. A run needs '
                                'exactly one comparison, and cannot start or '
                                'end on an operator.',
                          ),
                          _Rule(
                            'Length and difficulty pay',
                            'Multiply or divide multiplies the run by five, a '
                                'power by four. Runs past three bricks earn a '
                                'bonus per brick, and it climbs again at six '
                                'and at eleven. A bare 1 = 1 scores three.',
                          ),
                          _Rule(
                            'Cascades stack up',
                            'When falling bricks land on a new equation it '
                                'resolves by itself, and each link of the chain '
                                'is worth more than the last, up to five times.',
                          ),
                          _Rule(
                            'Bombs clear a cross',
                            'Swap a bomb with anything at all and it goes off, '
                                'taking its whole row and column. It does not '
                                'need to complete anything. Save them for a '
                                'board that has stopped offering you moves.',
                          ),
                          _Rule(
                            'Stone and diamond are locked',
                            'A locked brick shows you what it is but will not '
                                'move, and no equation can run through it. '
                                'Clear a run in any cell touching it and the '
                                'casing takes one hit — however many of its '
                                'neighbours went, it is still one hit. Stone '
                                'breaks in one, diamond in two. Breaking a '
                                'brick free pays four times what chipping it '
                                'does, and it plays normally from then on.',
                          ),
                          _Rule(
                            'Power-ups open locked bricks',
                            'A bomb or a lightning brick is the one thing you '
                                'can swap straight into a casing, and a blast '
                                'or a strike counts as a hit. That is the way '
                                'out of a board that has locked up on you.',
                          ),
                          _Rule(
                            'Lightning clears a kind',
                            'Swap the sparking brick with any other and every '
                                'brick showing that same glyph goes, wherever '
                                'it is. Swap two together and every digit '
                                'goes. Swap it into a bomb and it takes '
                                'whichever glyph is commonest instead. A blast '
                                'that reaches a lightning brick sets it off '
                                'too, so the two chain.',
                          ),
                          _Rule(
                            'NEXT is a promise, not a hint',
                            'The strip above the board is the brick queued for '
                                'each column, and it is exactly what will land '
                                'there. Plan two moves ahead.',
                          ),
                          _Rule(
                            'Endless gets stranger as you climb',
                            'The chip at the top right names the stage. Past '
                                '500 points the board stops leaning on = and '
                                'deals more < and >, then more of everything '
                                'else - and the locked bricks start arriving '
                                'with it.',
                          ),
                          _Rule(
                            'No moves means no score',
                            'If nothing can be completed, the board wipes and '
                                'deals a fresh one, and your score goes with '
                                'it. Operators cannot start or end an equation, '
                                'so a board crowded with them is a board '
                                'running out of room.',
                          ),
                          _PrivacyOptions(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "manage ad privacy" entry point.
///
/// UMP requires a way to reopen the consent form for users in a consent
/// region, and requires it *not* be shown to anyone else - so this renders
/// nothing at all unless the SDK says the option is required.
class _PrivacyOptions extends StatelessWidget {
  const _PrivacyOptions();

  @override
  Widget build(BuildContext context) {
    if (!ConsentService.privacyOptionsRequired) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: ConsentService.showPrivacyOptions,
          icon: const Icon(Icons.privacy_tip_outlined, size: 18),
          label: const Text('Manage ad privacy choices'),
          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
