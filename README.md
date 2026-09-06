# Easy Swapper

A math-equation match-and-swap puzzle: Candy Crush's swap-and-cascade loop over
the equation rules of [easy-mathriss](../easy-mathriss).

Every cell holds a digit, an arithmetic operator, or a comparison. Swapping two
adjacent cells is legal **only if it completes a valid equation** somewhere in
the affected rows and columns — `2 + 3 = 5`. Matched runs explode, columns
compact, new tiles drop in, and cascades chain.

```text
  7  +  ×  4  9  2  8  1
  3  ×  4  8  2  =  5  6
  1  +  1  =  2  7  4  9     <- swap the = and the 2, and 1+1=2 resolves
  8  6  1  +  5  3  9  2
```

## Documents

| | |
| --- | --- |
| [HELP.md](HELP.md) | How to play — the rules, in full |
| [STORE.md](STORE.md) | Store listing copy, screenshots, categories |
| [RELEASE.md](RELEASE.md) | What must be set up before shipping. **Read the blockers first** |

## Running it

```bash
flutter pub get
flutter run -d windows      # or chrome, android, ios
flutter test
flutter analyze
```

To watch the effects without playing, the game can drive itself:

```bash
flutter run -d windows --dart-define=autoplay=true --dart-define=bombpercent=25
```

`autoplay` plays one hinted move every 0.6s; `bombpercent` overrides the bomb
spawn rate so a blast does not take several minutes to turn up. Both are off by
default and exist only for eyeballing the juice.

Requires Flutter 3.41+ / Dart 3.11.4.

## Layout

The hard rule: **`lib/core/` imports nothing from Flutter or Flame.** That is
what makes the rules engine and the solver cheap to property-test, and it is the
one structural lesson carried over from easy-mathriss, where the entire game
lived in a 1354-line `render()` and a 1737-line `State`.

```text
lib/
├── core/                    PURE DART - no flutter, no flame
│   ├── math/                tokenizer, evaluator, equation finder
│   ├── board/               grid model, tile generation, move solver
│   ├── rules/               scoring
│   ├── levels/              level definitions and the shipped level list
│   └── session/             the turn loop and objective tracking
├── game/                    FLAME - camera, board, tiles, effects
└── ui/                      FLUTTER - overlays and theme
tool/
└── tune_weights.dart        difficulty measurement sweep
```

## The two things worth knowing

**1. The solver is load-bearing.** In a colour-matching puzzle any three like
tiles match, so legal moves are dense and deadlocks are rare. Valid *equations*
are rare, so a randomly refilled board deadlocks often and silently.
`core/board/move_solver.dart` brute-forces all ~112 swaps on an 8×8 board
(a few ms) and everything routes through it: deadlock detection, board
generation, the hint, and difficulty measurement.

**2. The tile distribution is measured, not guessed.** A uniform draw produces a
board with almost no findable equations, and the rules below bound it further.
`tool/tune_weights.dart` sweeps the distribution and reports the mean legal-move
count per operator tier:

```bash
dart run tool/tune_weights.dart            # opening-board move counts
dart run tool/tune_weights.dart playout    # moves survived before deadlock
```

Re-run both after changing the weights, the matching rules, or the board size.

## Board composition

Two rules bound what the generator and the refill may place, enforced on the
board rather than left to a weighted draw to hit on average:

- **Operators never exceed a third of the cells.** They cannot start or end an
  equation and cannot sit beside each other, so past that they stop enabling
  runs and start crowding out the digits those runs need.
- **Operators are not placed side by side.** Not absolute: refill relaxes it for
  comparison glyphs when the board is running short of them, because a board
  that runs out of comparisons is dead and one with a few pairs is merely
  untidy. Plain operators never get that exemption - a clumped operator is
  unlikely to be part of a run, so it is never cleared, and it accumulates.

Restock slots are *chosen*, not taken as they come: the emptiest-surrounded
cells go first, and comparisons skip corners, where they could never anchor a
run in either direction.

The playout tool exists because these rules can quietly strangle the game. An
early version held the no-adjacent rule absolutely and runs died of deadlock
after eight moves; with the floors and slot planning they survive 200 to 270.

## The next-drop preview

A strip above the board shows one brick per column - the tile that will drop
into that column next, at the same size it will be when it lands. It is a real
queue: that exact brick arrives, and it leads, coming to rest at the bottom of
whatever gap the clear leaves.

Column alignment is not free, and the playout tool measures the price. A brick
is committed to its column a turn before anyone knows which *row* it lands in,
so the refill cannot vet it against its neighbours the way it vets a live fill.
The only defence left is choosing **which columns** receive operators, which
`GameSession.replenishQueue` does by neighbourhood crowding. Drawing per column
blindly instead - the obvious implementation - cost three quarters of the
board's playable life.

What it costs as built, tier 2 with bombs, mean moves before a deadlock:

| preview | none | per-column |
| --- | --- | --- |
| moves survived | 252 | 192 |
| operators beside another | ~30% | ~47% |

The adjacency figure is the honest cost of the alignment. It can be pushed back
down by thinning the operators on the board, and the tool shows the
tenth-percentile run falling with it - a board that wipes is worse than one that
is untidy.

Two details that only matter once tiles are committed in advance, both of which
were bugs first:

- The cap counts board **plus** queue, so committed tiles can never overshoot
  it. The floors count the board **alone** - a queued operator has not landed
  yet, and treating it as if it had left the board starved while the queue held
  the difference.
- A cascade refills once per link and tops the preview up between them, so only
  the first refill of a turn draws from what the player saw before it.

## Running out of moves

A deadlock does not reshuffle. It announces itself, wipes the score and the
run's progress, and deals a fresh board. Because a bomb makes every adjacent
swap legal, a board holding one is never actually stuck, which is a large part
of why this is survivable.

## Bombs

A bomb tile detonates on **any** swap, clearing its whole row and column - a
cross - whether or not the swap completes an equation. Bombs caught in a blast
chain into it.

They arrive only on refill (never on the opening board) at
`TileGenerator.defaultBombChance`, and at most `GameSession.maxBombsOnBoard` sit
on the board at once. Both numbers are low on purpose: a bomb does not tokenize,
so every one on the board is a permanent hole in the equations the player can
still form.

Because a bomb makes every adjacent swap legal, the solver has to know about
them too - otherwise deadlock detection would reshuffle a board that was fine.

## Matching rules

Inherited from `easy-mathriss/lib/game/math_parser.dart`, with one change:
`findAllEquations` returns **every** non-overlapping match in a line, where the
original returned at most one. Tetris lands one piece at a time; a cascade board
resolves the whole grid at once.

- Adjacent digits read as one number: `1`,`9`,`9` is `199`.
- Precedence, no parentheses: `^` right-to-left, then `*` `/`, then `+` `-`.
- Exactly one comparison per run. `<` and `=` in adjacent cells fuse into `<=`.
- Every level uses a minimum run length of 3. A bare `1=1` scores 3,
  deliberately near-worthless, so players chase longer runs; objectives ask for
  length rather than forbidding short runs. Raising the minimum to 5 does not
  survive the operator cap - see the comment in `core/levels/level_data.dart`.
- Bomb tiles are drawn as vector art, not written as an emoji glyph: the bomb
  codepoint renders as a tofu box on Windows and is illegible at preview size.
- Score is `cells × multiplier` (compound ×3, exponent ×4, mul/div ×5, stacking)
  plus length tiers added afterwards, never scaled by the multiplier.

## Sound

Six clips in `assets/audio/`, taken from easy-mathriss: a swap, a rejected swap,
tiles landing, an equation clearing, a boom for deep cascades and bomb blasts,
and a game-over for the deadlock reset. Mute toggles from the HUD and persists.

Two things the manager does deliberately:

- **Every clip is checked against the asset manifest before loading.** A missing
  file otherwise throws inside the audio cache - loudly on web - and takes the
  whole load down with it. Here it degrades to silence and logs which clip is
  absent.
- **Players are pooled, one pool per clip.** `FlameAudio.play` builds and tears
  down a player per call, which a cascading match-three does dozens of times a
  second; on Windows that produced hundreds of platform-channel warnings per
  run. Pooling cut it to eight, one per clip at startup.

One clip plays per resolve step, never one per cell: a fifteen-cell blast firing
fifteen overlapping clears is noise, not feedback.

A handful of `xyz.luan/audioplayers/events ... non-platform thread` warnings
still appear at startup on Windows. Those come from inside the audioplayers
plugin, not from this code, and are harmless.

## Status

| Phase | Name | State |
| --- | --- | --- |
| 0 | Scaffold | done |
| 1 | Core engine, headless | done — 93 core tests |
| 2 | Playable board | done — drag/tap to swap, cascade, refill; 10 widget tests |
| 3 | Juice | glass blocks, shatter, shockwaves, bundled Sour Gummy text, sound |
| 4 | Levels and meta | 20 levels defined; level select and persistence pending |
| 5 | Specials | bomb done; row/column/wildcard specials not started |
| 6 | Polish | ads, leaderboards, in-game help and store copy done; icon and signing outstanding |

Level select and persistence of progress (Phase 4) are the main gap: the twenty
levels are defined but only endless mode is reachable from the UI.

Before shipping, work through [RELEASE.md](RELEASE.md). The tree is currently
signed with the debug key, has no app icon, and every AdMob and leaderboard
identifier is a placeholder.
