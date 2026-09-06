/// The in-game rules screen.
///
/// Kept in sync with `HELP.md`, which is the longer version and the source for
/// the store listing. This one is trimmed to what a player needs mid-game.
library;

import 'package:flutter/material.dart';

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
                            'NEXT is a promise, not a hint',
                            'The strip above the board is the brick queued for '
                                'each column, and it is exactly what will land '
                                'there. Plan two moves ahead.',
                          ),
                          _Rule(
                            'No moves means no score',
                            'If nothing can be completed, the board wipes and '
                                'deals a fresh one, and your score goes with '
                                'it. Operators cannot start or end an equation, '
                                'so a board crowded with them is a board '
                                'running out of room.',
                          ),
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
