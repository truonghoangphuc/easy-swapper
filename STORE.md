# Store listing copy

Written for the game as it stands: endless mode, a banner ad, and platform
leaderboards. If level select ships (see [RELEASE.md](RELEASE.md)), the lines
marked **[levels]** are the ones to swap in.

> **The copy was rewritten when ads were added.** An earlier draft promised "no
> ads" and "nothing leaves your device". Both became false the moment AdMob and
> Play Games went in, and a store listing that misdescribes data handling is a
> policy violation, not a typo.

Character counts are the store limits, not suggestions — Play truncates silently
and App Store Connect refuses to save.

---

## App name

**Google Play** (30 max) and **App Store** (30 max):

```
Easy Swapper
```

## Subtitle — App Store only (30 max)

```
Swap tiles, build equations
```

Alternatives, same length budget:

```
Match three, but it's maths
Make the numbers add up
```

## Short description — Google Play (80 max)

```
Swap the bricks to build real equations. Match three with actual arithmetic.
```

*(76 characters.)*

Alternatives:

```
A match-three where the tiles are numbers and the matches are real sums.
Slide numbers together until the maths works. Then watch it all explode.
```

## Promotional text — App Store (170 max, editable without review)

```
Every tile is a number or an operator. Swap two, and if the row adds up, it
detonates. Bombs clear a whole cross. One rule, endless boards, no timers.
```

---

## Long description (Google Play, 4000 max — this is ~1,900)

```
Easy Swapper is a match-three puzzle where the matches are real arithmetic.

Every brick on the board is a digit, an operator, or an equals sign. Swap two
neighbours, and if the swap completes a true equation somewhere in that row or
column, the bricks shatter and new ones fall in. 2 + 3 = 5 clears. 9 > 4 clears.
1 = 1 clears too, but it is worth almost nothing — the long runs are where the
points are.

There is no timer and nothing to buy. Just a board, and the question of what
adds up.

HOW IT WORKS

• Drag a brick into its neighbour, or tap one then the other
• A swap is only legal if it completes an equation — nothing else moves
• Adjacent digits read as one number, so 1 and 9 and 9 make 199
• Normal precedence applies: 1 + 2 x 3 is 7, not 9
• Longer runs and harder operators multiply your score
• Clears cascade — falling bricks that land on a new equation chain it

BOMBS AND LIGHTNING

Now and then a bomb arrives. Swap it with anything at all and it detonates,
clearing its entire row and column. Bombs caught in the blast chain into it.

Rarer still is the lightning brick. Swap it onto any brick and every brick
showing that same glyph is destroyed, wherever it sits on the board. Swap two
together and every digit goes at once, and a bomb blast that reaches one sets
it off rather than wasting it.

LOCKED BRICKS

Deeper into an Endless run, bricks start arriving sealed. You can see what is
trapped behind the stone or the diamond, but it will not move and no equation
can run through it. Resolve a run beside it and the casing cracks — stone
takes one hit, diamond two. A bomb or a lightning brick is the only thing you
can swap straight into one, which is how you open a board that has locked up.

STAGES

Endless changes as you climb. The board starts leaning on equals; past 500
points it deals far more greater-than and less-than, then multiply and divide,
then lightning. Deeper stages pay substantially better per move.
They are the way out of a tight board, so spend them when you are stuck, not
when you are winning.

THE NEXT ROW

A strip above the board shows the brick queued for each column. It is not a
hint — it is a fact. That exact brick drops into that exact column the moment
the column has space. Plan two moves ahead instead of one.

WHEN NOTHING WORKS

If the board reaches a state where no swap completes anything, it says so,
clears itself, and deals a fresh one. Your score goes with it. Watch the
operators: they cannot start or end an equation, so a board thick with them is
a board running out of room.

COMPETE

Your best run goes to the Game Center or Play Games leaderboard, so you can see
where it lands. Sign-in is optional and the game is complete without it.

WHAT IS NOT IN HERE

No timers. No lives to wait for. No pop-ups asking you to rate it. No account
needed to play, and nothing to buy. There is one banner ad at the bottom of the
screen, and it never covers the board.

Built with Flutter and Flame.
```

**[levels]** If level select ships, replace the second paragraph with:

```
Twenty hand-tuned levels, each with a move budget and a goal — reach a score,
clear a number of equations, or put a particular operator to work. Or drop into
endless mode and play until the board runs out of ideas.
```

---

## App Store description

Same body as above. Apple's description does not render bullet characters any
differently, so `•` is fine. Lead with the first two paragraphs — the App Store
truncates after roughly three lines before the "more" link.

## Keywords — App Store only (100 max, comma separated, no spaces)

```
math,maths,puzzle,match3,numbers,equation,arithmetic,brain,logic,swap,tiles,sums
```

*(79 characters.)* Do not repeat the app name — Apple already indexes it.

`noads` and `offline` were in an earlier draft and are gone: there is a banner
now, and the leaderboard needs a connection. Keywords that contradict the app
are a rejection risk and, worse, they set up a one-star review.

---

## Category and rating

| | Google Play | App Store |
| --- | --- | --- |
| Category | Games → Puzzle | Games → Puzzle (secondary: Education) |
| Rating | Everyone / PEGI 3 | 4+ |
| Ads | **Yes — banner** | **Yes — banner** |
| In-app purchases | None | None |
| Third-party login | Play Games (optional) | Game Center (optional) |

Content questionnaires: no violence, no user content, no communication
features, no location, no purchases. The bomb is a cartoon and clears tiles;
it is not depicted violence and does not change the rating.

**Both stores must be told the app contains ads.** Play has a dedicated "contains
ads" declaration that also puts a badge on the listing; the App Store asks during
the privacy questionnaire. Getting this wrong is a takedown, not a warning.

**Do not mark it as designed for children.** AdMob's default configuration is
not compliant with Play's Families policy or COPPA. If you ever want the Family
category, ads must be reconfigured with `tagForChildDirectedTreatment` and the
whole privacy story revisited.

---

## Screenshots

Six, in this order — the first two are what most people ever see:

1. **A mid-clear board**, shards flying, "EXCELLENT!" on screen. Sells the
   feel in one frame.
2. **A clean board with the NEXT strip visible.** Shows the mechanic is
   readable and the tiles are legible.
3. **A bomb mid-detonation**, cross blast lit up.
4. **A long equation resolving** — something like `12 + 34 = 46` — to show it
   is real arithmetic, not colour matching.
5. **A cascade**, "INCREDIBLE!" with a chain multiplier.
6. **The deadlock reset**, "NO MOVES LEFT". Honest about the stakes.

Capture at device resolution from a release build, not the debug one — the
debug banner is off, but debug builds render slower and the particle timing
will not look right.

`--dart-define=autoplay=true --dart-define=bombpercent=25` makes the game play
itself, which is the easy way to catch frames 1, 3 and 5.

## Feature graphic — Google Play (1024×500)

The board at an angle on the dark background, three or four bricks lifted out
and mid-shatter, `2 + 3 = 5` legible among them. No screenshot frame, no device
mockup — Play overlays its own UI on this and busy art disappears under it.
