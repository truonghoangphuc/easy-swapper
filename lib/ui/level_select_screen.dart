import 'package:flutter/material.dart';

import '../core/levels/level_data.dart';
import '../main.dart'; // To access GameScreen
import '../services/progress_service.dart';
import '../services/save_game_service.dart';
import 'theme/app_theme.dart';

class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  @override
  Widget build(BuildContext context) {
    final highestUnlocked = ProgressService.highestUnlockedLevel;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bg.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'EASY SWAPPER',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 48),
            _ModeButton(
              title: 'CHALLENGE',
              subtitle: highestUnlocked > levels.length
                  ? 'ALL CLEARED'
                  : 'LEVEL $highestUnlocked',
              onTap: () {
                final targetLevel = levelById(highestUnlocked) ?? levels.last;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameScreen(level: targetLevel),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
            const SizedBox(height: 24),
            _ModeButton(
              title: 'ENDLESS',
              subtitle: 'INFINITE PLAY',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GameScreen(level: endlessLevel),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextButton(
                onPressed: () async {
                  await SaveGameService.clear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved game cleared!')),
                    );
                  }
                },
                child: const Text(
                  'Clear Resume Data',
                  style: TextStyle(color: AppColors.textDim),
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

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.boardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accent, width: 2),
          ),
          child: Center(
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
