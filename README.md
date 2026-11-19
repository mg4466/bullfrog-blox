# Voxel Q*bert

A Q*bert clone written from scratch in Godot 4: 28 cubes, four diagonal hops,
red balls, a snake that hunts you down, and two spinning discs that carry you
back to the top.

Every model in the game is a voxel grid built in code, and every sound is a
square wave generated at startup. There are no imported models, textures or
audio files — the repository is source only.

![The board mid-round](docs/board.png)

## Play

Requires [Godot 4.7](https://godotengine.org/download) (a plain install is
enough; no .NET build, no plugins).

```bash
git clone https://github.com/mg4466/qbert-voxel.git
cd qbert-voxel
godot --path .
```

On Arch, `sudo pacman -S godot` works; otherwise drop the official Linux
binary somewhere on your `PATH`. You can also open `project.godot` in the
editor and press F5.

## Controls

| Key | Action |
| --- | --- |
| `Q` / numpad `7` | hop up-left |
| `E` / numpad `9` | hop up-right |
| `A` / numpad `1` | hop down-left |
| `D` / numpad `3` | hop down-right |
| `Space` | start |
| `R` | restart after game over |
| `Esc` | quit |

Mashing a direction during a hop queues one extra hop, the way the arcade
joystick did.

## Rules

Hop on every cube to paint it the target colour before the enemies get you.

* **Tiles.** Level 1 needs one hop per cube. Level 2 needs two (blue → green →
  gold). From level 3 the three states *cycle*, so a third hop resets the cube —
  you have to plan the order you walk in.
* **Red balls** hop downhill at random. They kill you on contact, but you can
  squash one by landing on it.
* **Slick** (green, from level 2) does the same, and flips the cube it lands on
  one state backwards.
* **Coily** (from level 3) drops in as an egg, hatches at the bottom of the
  pyramid, then hops along the shortest route to you. The only way to kill it
  is to jump onto a disc: it follows you off the edge and falls.
* **Discs** sit just off the two bottom corners. Landing on one flies you to the
  apex; each disc is single-use per round.
* Falling off the edge costs a life. Three lives.

| Event | Points |
| --- | --- |
| Hop onto a cube | 25 |
| Squash a ball or Slick | 100 |
| Ride a disc | 500 |
| Kill Coily with a disc | 500 |
| Clear a round | 1000 + 250 per level |

The high score is saved to the Godot user directory (`user://voxel_qbert.cfg`).

## Tests

Two headless suites, both part of the repository:

```bash
# 312 checks over the pure rules: pyramid shape, projections, state rules,
# hop arcs, chase AI, voxel mesh geometry.
godot --headless --path . --script res://tests/test_logic.gd

# Boots the real game, plays it with an autopilot until a round is cleared,
# then dies on purpose until game over and checks that restarting is clean.
godot --headless --path . res://tests/playthrough.tscn --fixed-fps 60 --quit-after 8000
```

`tests/capture.tscn` regenerates the screenshots in `docs/`, and
`tests/measure.tscn` prints the screen geometry (cube size, row spacing, board
bounds) so layout regressions can be checked numerically.

## How it is built

| File | Responsibility |
| --- | --- |
| `scripts/board.gd` | Pure rules: which cubes exist, the four move vectors, world projection, tile-state transitions, Coily's greedy chase |
| `scripts/hop.gd` | Jump maths (linear travel plus a parabolic bump) |
| `scripts/voxel_builder.gd` | Sparse voxel dictionary → `ArrayMesh` with culled faces and vertex colours |
| `scripts/voxel_models.gd` | The cast: player, red ball, Slick, Coily's egg and snake, disc |
| `scripts/game.gd` | The conductor: phases, scoring, enemy scheduling, level flow |
| `scripts/tile.gd`, `player.gd`, `enemy.gd` | Presentation for each thing on the board |
| `scripts/hud.gd`, `synth.gd` | Overlay and procedural sound |

The full walkthrough — coordinate system, why the stage is rotated 45°,
how the tests caught two real layout bugs — is in
[docs/LEARNING.md](docs/LEARNING.md).

## Not implemented

* No attract mode or demo playback, no music, no gamepad remapping.
* One board shape only: every level is the 7-row pyramid (levels differ in
  tile rules and enemies, not in geometry).
* No Coily variants (the arcade's second snake), no level intermissions.
* When the board empties, a replacement red ball arrives on a timer rather than
  the arcade's scripted waves.

## License

MIT — see [LICENSE](LICENSE).
