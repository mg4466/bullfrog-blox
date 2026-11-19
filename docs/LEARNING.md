# A guided tour of Voxel Q*bert

This is the "why", not the "what". The code is commented file by file; this
document is for reading end to end, ideally with `scripts/game.gd` open in
another window.

If you only take one thing away: **the game is a set of integer coordinates and
a set of rules, plus a thin layer that draws them.** Almost every hard problem
here was solved in the rule layer, where a headless test could check it.

---

## 1. The board is a plane of coordinates, not a grid of tiles

Q*bert's pyramid looks like 28 cubes arranged in a triangle. The tempting model
is a 2D array: row 0 has 7 cubes, row 1 has 6, and so on. The problem starts the
moment you need to ask "what is one hop down-left from here?" — in a ragged 2D
array that question has a different answer on every row, and the edge cases
(a hop off the side of the pyramid) are all different.

Instead, every cube is a `Vector3i(x, y, z)` where

```
x >= 0, y >= 0, z >= 0        and        x + y + z == 6
```

For a 7-row board that sum is 6, and the set of non-negative integer solutions is
exactly 28 — the triangle. `Board.pyramid(7)` enumerates it.

The four moves are constant vectors:

```
down-right (1, -1, 0)    down-left (0, -1, 1)
up-right   (0,  1, -1)   up-left  (-1, 1, 0)
```

Each changes two coordinates and leaves the third alone. Because the sum is
constant, *every move stays on the plane by construction* — there is no
"wrap-around" case to handle. And "is this cube on the board?" becomes one
integer test, `x >= 0 and y >= 0 and z >= 0`, instead of a lookup in a triangular
table.

What this buys you concretely:

* Hop legality is `grid.has(coord + dir)`. Off the edge is simply "not in the
  dictionary", which is also exactly the condition for falling to your death.
* Neighbours are a loop over four constants; corners have one neighbour, edges
  two, interior cubes four. That falls out of the geometry, it is not
  special-cased.
* Coily's chase is Manhattan distance in three integers. No pathfinding, no
  navigation mesh.
* The same rules would work unchanged on a ziggurat, a pyramid with a bridge, or
  two stacked layers, because a coordinate does not care what shape the set is.

`Board` is a `RefCounted` with static functions and no scene tree access. That is
what makes it runnable in `--headless` mode with no GPU.

---

## 2. Showing a plane to a camera: the two bugs worth knowing

The board is flat. The camera is isometric. Turning `Vector3i` into a screen
position is where the interesting mistakes live, and this project made both of
them before the screenshots looked right.

### Bug one: the rows have to be horizontal

`Board.world_pos()` lays the board out on the world's x/z plane:

```
row  = 6 - y        (0 = apex, 6 = base)
index = x           (0 .. row, left to right)
x_world = (index - row / 2) * SPACING_X
z_world = (row - 3) * SPACING_Z
```

The camera sits on the `(1, 1)` diagonal — classic isometric — so its "screen
right" direction is `(x - z) / sqrt(2)`. If the board's own axes are world x and
world z, then a row (pure x) projects diagonally across the screen and the
pyramid leans. That is bug one, and it is visible in one glance.

The fix is one line in `game.gd`:

```gdscript
_stage.rotation.y = PI * 0.25
```

Rotating the stage 45° puts the board's x axis exactly along the camera's screen
right, and its z axis exactly along screen depth. Now rows are horizontal and the
pyramid is symmetric. None of the coordinates changed — the projection layer
absorbed it. (Aim the camera through the stage, too: `_camera` targets
`_stage.transform * Vector3(0, 0, 0.5)`. Aiming at a raw world point offsets the
board sideways by half a unit, which presents as "the pyramid is not centred" and
is maddening to debug.)

### Bug two: foreshortening is not optional

A camera looking down at 30° compresses depth by `sin(30) = 0.5`. If the depth
step between rows equals the horizontal step between cubes, the rows overlap and
the board reads as a pile of squashed rectangles. The step has to compensate:

```gdscript
const TILE_SPACING_X := 1.0
const TILE_SPACING_Z := TILE_SPACING_X / 0.5   # twice as deep, appears square
```

`tests/measure.tscn` prints the numbers that prove it: same-row step 90.9 px
horizontally, row step 90.9 px vertically, board centre exactly on the screen
centre, content inside the HUD margins. When you change the camera, run it — the
alternative is squinting at a screenshot and guessing.

---

## 3. Voxels: a dictionary and a face-culling loop

`VoxelBuilder.build()` takes `{Vector3i: Color}` and emits a single `ArrayMesh`.
For every cell and every one of the six faces, if the neighbouring cell exists,
skip the face. That is the whole algorithm.

Two details that are easy to get wrong:

* **Winding.** Each quad is listed counter-clockwise as seen from outside. Godot
  culls back faces, so a reversed winding makes a model disappear from some
  angles and look inside-out from others. The corner indices in `FACE_DEFS` are
  worth checking against a sketch once.
* **SurfaceTool has no implicit fan for `PRIMITIVE_TRIANGLES`.** A quad must be
  emitted as six vertices `(a, b, c, a, c, d)`. Emitting four and hoping for a
  fan produces half a model.

Models are authored in a small grid and normalised by the builder: centred in
x/z, floor at `y = 0`. That convention is why placing a character is just "put
the node at the cube's top surface" — no per-model offsets, no pivot guessing.
The test suite asserts it (`bounds.position.y == 0`, centred in x and z) and
asserts that characters are narrower than a tile so they never overlap their
neighbours.

The tile cubes are deliberately *not* voxel-built. They are `BoxMesh`es with one
material each, because a tile has to change colour independently and 28 of them
need to be cheap. Voxels are for the characters, where silhouette matters.

---

## 4. The phase machine, and why tweens need a leash

`game.gd` has five phases: `READY`, `PLAYING`, `DYING`, `CLEAR`, `GAME_OVER`.
Every transition is explicit, and every handler checks the phase before acting.
This matters because the game is driven by tween callbacks: a hop that finishes
after the player died, a level-clear timer that fires after a restart, an enemy
hop that resolves after its level was freed.

The bug the headless soak test found is instructive. Killing an enemy frees its
node; the hop tween that was moving it keeps running for another frame or two,
because the tween belongs to the *game*, not the enemy. The result:

```
ERROR: Lambda capture at index 2 was freed. Passed "null" instead.
SCRIPT ERROR: Invalid assignment of property 'position' on a base object of type 'Nil'.
```

The fix is `HopEnemy.track_motion()` plus `_exit_tree()`: the enemy registers the
tween that moves it, and kills it when it leaves the tree. Anything that owns a
tween which captures a node must be able to cancel it. (Same idea for the
level-clear wave: it connects `tile.celebrate` to `SceneTreeTimer`s, so the
timers are short and the tiles outlive them.)

Input buffering is the same kind of thinking from the player's side: one slot of
buffered direction, replay it on landing, never more than one. Two slots turns a
double-tap into an unwanted hop into a snake; zero slots makes the game feel like
it is ignoring you.

---

## 5. Rules as data

Level behaviour is a table, not a pile of `if level ==` branches:

```gdscript
static func next_state(state, level, state_count):
    if level >= 3:
        return (state + 1) % state_count     # cycles: overstepping is punished
    return mini(state + 1, state_count - 1)  # monotonic: one or two hops, then done
```

Palettes live in `Board.LEVEL_COLORS` as hex strings (a `const` cannot call
`Color()`, so the conversion happens in `palette_for()`). Enemy counts and speed
live in `_level_plan()` in `game.gd`. Adding a fourth palette or a fourth
difficulty knob is a one-line change in data, and the tests already cover the
rule function's boundaries.

The chase AI is one function:

```gdscript
for next in neighbours:
    distance = |dx| + |dy| + |dz|
    keep the smallest
```

It is greedy, not optimal. That is a design decision, not laziness: a perfect
chaser would make the disc the only survivable strategy, and the arcade game's
snake was beatable by out-turning it. When you tune difficulty, tune the hop
interval and the greedy rule, not the pathfinding.

---

## 6. Sound from arithmetic

`Synth` renders square/saw/noise waves into `AudioStreamWAV` at 22 kHz, 16-bit
mono. Each spec is `{freq, dur, vol, sweep, wave}`; `sweep` multiplies the
frequency across the tone (2.0 = an octave up), which is what makes "fall" sound
like falling and "step" sound like progress. A 4 ms attack avoids the click of a
square wave starting at full amplitude, and a linear decay ends it cleanly.

Streams are cached by key at first use, and a small round-robin pool of players
lets overlapping blips (hop + step + squash in one frame) play at once. This is
roughly how arcade hardware did it: a handful of voices, fixed waveforms, no
samples.

---

## 7. Testing a game without a person at the keyboard

Two layers:

1. **`tests/test_logic.gd`** extends `SceneTree` and runs with `--script`. It
   checks the pyramid (28 unique cubes, right row counts, every move preserving
   the plane), the projection (no two cubes on the same screen point, symmetric
   base, square grid), the state rules per level, the hop arc (starts and ends
   exactly, peaks at the requested height, never dips below takeoff), the chase
   AI, the disc placement (off-board but one hop from a cube), and the mesh
   geometry (36 vertices for one voxel, 60 for two touching voxels).
2. **`tests/playthrough.tscn`** boots the real scene and plays it: a
   breadth-first autopilot clears rounds, then a death drill walks off the edge
   until game over and verifies the restart resets lives, score, level and the
   board.

Both caught bugs that no amount of staring would have found: the freed-lambda
crashes above, and an autopilot that could not reach the base corner because
"walk towards the target" is not a valid strategy on a triangle.

The tests are not decoration. They are why the projection and the phase machine
could be rewritten at speed without re-testing by hand.

---

## 8. Exercises

* **New board shape.** `Board.pyramid(rows)` is the only place that assumes a
  triangle. Try a hexagon (all coordinates with `max(x,y,z) <= 3` and a fixed
  sum) and see how much of the game keeps working. Expected answer: everything
  except art direction.
* **A second snake.** The arcade's green Coily could be a `coily` enemy with a
  different step rule (chase, but prefer not to land where the player can squash
  it). The enemy type is a string and the decision is one function.
* **Camera rotation.** Rotate `_stage` by 90° and swap the four input directions
  to match. The coordinate layer does not care; this is purely a mapping between
  keys and `Board.DIRECTIONS`.
* **Export a build.** Add an `export_presets.cfg` for Linux/Windows and check
  that `user://voxel_qbert.cfg` still lands somewhere writable.
