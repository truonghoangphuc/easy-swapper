# How to play Easy Swapper

Every brick is a digit, an operator, or a comparison. Swap two neighbours to
make the maths work, and the bricks that made it work explode.

---

## The one rule

**A swap is only allowed if it completes a true equation.** Drag a brick into
the one beside it — up, down, left or right — or tap one brick and then its
neighbour. If the swap makes an equation somewhere in the affected row or
column, it resolves. If it does not, the bricks bounce back and the move costs
you nothing.

```
 7  +  ×  4  9
 3  ×  4  8  2
 1  +  1  =  3      ← swap the 3 and the 2 above it …
 8  6  1  +  2

 1  +  1  =  2      ← … and 1 + 1 = 2 resolves
```

## Reading a run

A run is any straight line of three or more bricks, read left to right or top
to bottom.

- **Digits side by side make one number.** `1` `9` `9` is one hundred and
  ninety-nine, not three separate digits. This is how the long, high-scoring
  runs get built.
- **Normal precedence applies.** `1 + 2 × 3` is 7, not 9. Powers first, then
  multiply and divide, then add and subtract. There are no brackets.
- **Exactly one comparison per run.** `1 = 1 = 1` is not an equation, it is two
  of them fighting; the game takes the leftmost.
- **Both sides must be complete.** A run cannot start or end on an operator.
- Dividing by zero is not an equation, so `4 / 0 = 0` does nothing.

Inequalities count as equations too, wherever the game has given you `<` and
`>`. `9 > 4` resolves. So does `12 < 50`.

## Scoring

Every brick in the run scores, and the run is multiplied by what it took to
build:

| The run contains | Multiplier |
| --- | --- |
| × or ÷ | ×5 |
| a power | ×4 |
| a two-part comparison such as `<=` | ×3 |

Those stack. A run using both division and a power scores twenty times its
length.

On top of that, length pays:

| Length | Bonus per extra brick | |
| --- | --- | --- |
| 4 and beyond | +1 | GOOD JOB |
| 6 and beyond | +2 more | EXCELLENT |
| 11 and beyond | +5 more | OH MY GOD |

So a bare `1 = 1` scores three points. It is a legal move and almost never the
right one.

**Cascades multiply everything.** When the falling bricks land on a new
equation it resolves by itself, and each link of the chain is worth more than
the last, up to five times. Three links deep gets you INCREDIBLE.

## Bombs

A bomb turns up on the board now and then — at most three at a time.

**Swap a bomb with anything at all and it goes off.** It does not need to
complete an equation; that is the point of it. The blast clears the bomb's
entire row *and* its entire column, and any other bomb caught in the cross
chains into the explosion.

A blast pays a flat rate per brick rather than the equation multipliers, so it
is worth points but never as many as the run you could have built. Save bombs
for a board that has stopped offering you anything.

## Lightning

The sparking brick is rarer than a bomb — never more than two on the board.

**Swap it with any brick and every brick showing that same glyph is
destroyed**, wherever it is. Swap it onto a 7 and every 7 goes. It pays more
per brick than a bomb does, because a bomb always clears a full cross while a
lightning strike only gets as much as the board happens to be holding.

Swap two of them together and every digit on the board goes at once.

Swap it with another power-up, which has no glyph of its own, and it falls
back to whichever glyph is commonest at that moment.

A bomb blast that reaches a lightning brick **sets it off** rather than
destroying it, the same way one bomb chains into another. A cross through two
of them is worth setting up.

## Stone and diamond

Some bricks arrive sealed. A **stone** brick is behind one layer, a
**diamond** behind two.

You can see what is trapped in there, but it will not move and no equation can
run through it. A sealed brick is a hole in the board until you break it out.

**Resolve a run in a cell next to it and the casing takes a hit.** Up, down,
left or right — not diagonally. However many of its neighbours cleared at
once, it is still one hit per casing per step, so surrounding it does not
speed things up; hitting it on separate turns does.

A bomb blast or a lightning strike counts as a hit too, and a power-up is the
only thing that can be swapped straight into a casing. That is what makes
bombs and lightning the reliable answer to a board that has locked up.

One hit breaks stone. A diamond takes one hit to become stone, and another to
come free. Breaking a brick out pays four times what chipping one does, and
the freed brick is ordinary from the next scan on — it cannot join the very
run that freed it.

Power-ups are paid for what they actually destroy, so a blast that only
cracks casings scores the cracks, not the bricks it failed to break.

Sealed bricks only appear in Endless, and only once you are past the first
stage.

## Stages, in Endless

The chip at the top right names the stage you are in, and it changes as your
score climbs.

The board starts leaning on `=`. Past **500** points it starts dealing many
more `<` and `>`, which makes true statements far easier to find, and the
first sealed bricks arrive with them. Further up, multiply and divide get more
common, lightning appears, and more of the board is sealed at any one time.

Deeper stages are not harsher — they pay substantially better per move. A
deadlock wipes your score, and it takes the stage back to the start with it.

## The NEXT strip

The row above the board is not a hint. It is the brick queued for each column,
and it is exactly what will arrive there.

When a clear leaves a gap in a column, that column's brick drops in first and
falls to the bottom of the gap, with anything else stacking on top. Then a new
brick takes its place in the strip.

Use it. Knowing that a `=` is about to land in the fourth column changes which
swap you should make now — and a sealed brick in the strip is a warning that
one of your columns is about to lose a cell.

## Running out of moves

If the board reaches a point where no swap completes anything, it says **NO
MOVES LEFT**, clears itself, and deals a fresh board. **Your score resets with
it.**

You can see it coming. Operators cannot start or end an equation and they never
combine with each other, so a board crowded with `+`, `=` and `<` is a board
with fewer and fewer places to put a number. When the operators start to
outnumber the room you have to work with, cash in a bomb.

## Small things

- Leave the board alone for a few seconds and the best available swap starts
  pulsing.
- The speaker button in the corner mutes the sound, and it remembers.
- Nothing is timed. Take as long as you like.

---

## Brick colours

Each digit has its own colour so a row reads as distinct objects rather than a
wall of numbers. Operators are deliberately duller — they are the punctuation
of an equation, not the substance.

| | |
| --- | --- |
| 0–9 | a colour each, from slate through to rose |
| `+` `-` `×` `÷` | blue-grey |
| power | green |
| `=` `<` `>` | purple |
| bomb | red, with a lit fuse |
