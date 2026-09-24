# Voxel Minecraft (Flutter) — a Minecraft clone, ported to `flutter_scene`

**What this is.** A self-contained Flutter project on branch `poc_cubeworld` of the
Dawnforge Flutter repo, in its folder `poc_cubeworld/` (the package is `voxel_game_minecraft`). It is the Flutter twin
of the Godot POC at `~/Documents/godot/remottely/dawnforge_cubeworld_poc/poc_cubeworld/`
(branch `poc_cubeworld` of `tessera_project`): same game, same block table, same save
format, same probe flags, ported file by file onto
[`flutter_scene`](https://pub.dev/packages/flutter_scene) (Flutter GPU / Impeller).
It shares NOTHING with `lib/src/core` of the study track on purpose: the brief is the same
as the Godot one — *"não foque em arquitetura, foque em entregar o clone do jogo
funcionando"*. Nothing here is merged as-is.

**The kit.** The voxel packages this app grew — `voxel_engine`, `voxel_scene`,
`sound_recipes` and `voxel_game` — live in [`packages/voxel_game/`](packages/voxel_game/),
a pub workspace of its own with its own [README](packages/voxel_game/README.md) and rules,
laid out to leave for a repository of its own. This app is not part of that workspace: it
consumes the kit through four `dependency_overrides` by path in `pubspec.yaml`.

**Lineage.** Every file in `lib/src/` is a port of its Godot sibling (`src/**.gd` and
`csharp/*.cs`). The C# `TerrainGenerator` and `ChunkMesher` became pure-Dart classes that
run on a pool of isolates (`chunk_worker.dart`); the GDScript autoloads became static
tables; Godot's `CanvasItem` HUD became a `CustomPainter`; ENet became TCP + JSON lines.
`ROADMAP.md` is the stage list and the live status of the port.

## Running

```bash
cd poc_cubeworld
flutter run -d macos                                   # Flutter GPU is enabled in Info.plist
flutter build macos --debug                            # then:
build/macos/Build/Products/Debug/voxel_game_minecraft.app/Contents/MacOS/voxel_game_minecraft \
  --screenshot=/tmp/shot.png --frames=300 --seed=1337 --new    # self-report, exits when captured
flutter test                                           # tables, generator, mesher (pure Dart)
```

Probe flags (same as the Godot POC, plus a few for tuning): `--screenshot=<png> --frames=N
--seed=N --radius=N --class=warrior|ranger|mage|rogue --time=0..1 --fly --fp --tp=x,y,z
--look=yaw,pitch --hold=<item> --swing=N --settle=N --map --open-inventory --fire=primary|secondary --stage16
--strike --stage18 --stage19 --stage20 --ride --stage21a --kind=5..9 --biome=N --stage21b --stage22 --stage23 --stage24 --slot=<name> --open-map --open-settings --stage25 --reject-one --stage26 --shot=biome|village|trade|portal|fortress|cavern|tutorial --stage27 --stage28 --stage29 --kind=4 --stage30 --title-probe --stage31 --no-light --shot=room|cave --stage32 --shot=combat|mining --open-worlds --open-credits --credits-t=N --no-tutorial --move-probe --model-probe --map-probe --anim-probe --outline-probe --item-probe --reach-probe --underwater --climb --playground --shots=a,b,... --pg-checks --open-playground --weather=clear|rain|storm|snow --journal=0..4 --host --join=<ip> --wait-peer --trace --touch --touch-probe --pace-probe`, and for the look: `--sun=k --amb=k
--tm=aces|agx|neutral|linear --fogd=density --noshadow --shadowcache=0|1
--casterfaces=front|back`. The debug app forwards the process arguments to Dart
(`MainFlutterWindow.swift`), so no `--` separator is needed.

`--pace-probe` prints `[probe] pace: shown=N rendered=M` every 60 painted frames: how many
frames drew a finished scene picture and how many new scene frames went to the GPU
(`PacedScene`, `lib/src/ui/paced_scene.dart`; about half on a 120 Hz display). With
`--title-probe --open-playground` it is the check for the glyph-atlas noise of session 28:
run two other copies of the app first to load the GPU, then read the panel's text.

On-screen controls: a phone or a tablet always shows them; `--touch` turns them on from a
desktop so the layout can be seen and captured. The stick walks (pushed to the rim it runs),
the right-hand cluster is interact / sneak (it latches) / jump, the bag at the end of the
hotbar opens the inventory, a hotbar square selects it and the top-left button pauses. On the
world itself: tap = use what the crosshair points at (a swing when that is a creature), hold =
mine, drag = look. Everything else is still keyboard or gamepad only.

`--touch-probe` plays that scheme with a scripted finger and prints what the simulation did
with it: the block a finger dug by staying put, the block a tap put back, the damage a tap on
a creature dealt, the radians a drag turned, that a cancelled touch decided nothing, and the
metres the on-screen stick and jump button moved the body. Its last line,
`touch one-shot: N of 20 taps reached the simulation at F fps`, is the press-delivery check:
it must read 20 of 20 at any frame rate — it read 0 of 20 at 120 fps while a frame that ran
no simulation step still drained the one-shots. Since `GameInput` is `voxel_game`'s
`InputMap<GameAction>`, this probe is the kit's touch scheme running, not a copy of it.

Stage 30 probes: `--stage30 --title-probe --frames=200 --settle=10 --screenshot=<png>` runs the
title half (the buttons, a world created / listed / renamed / deleted through `Worlds`, the
credits rows parsed from the bundled `ROADMAP.md`), then starts a creative mage world in
slot `probe30_stats` through the same path as Play (damage ignored, a free block, fly, the
tutorial driven through seven steps and skipped, the stats saved and read back in a rebuilt
session; the slot is removed at the end, the tutorial flag goes to `settings_probe30.cfg`).
Captures: `--title-probe --screenshot=<png>` (the title) · `--title-probe --open-worlds` (the
world list with the form) · `--title-probe --open-credits [--credits-t=seconds]` (Flutter
only) · `--new --seed=42 --stage30 --shot=tutorial` (the card on step 4).

The first-person hand has no probe of its own: it is a world-space node placed against the
camera basis every frame, so any capture shows it. `--fp --hold=<item>` puts a named tool or
block in the fist, and `--swing=N` starts a swing and waits N frames before the shutter, which
is how the arc across the corner of the screen was checked frame by frame.

`--item-probe --screenshot=<png>` fills the hotbar and the bag with a spread of item kinds and
drops one of each on a cleared pad. For every item it prints the model size, the drop scale and
the icon face count, then measures which way the first-person pickaxe head points in the camera's
axes (it must not point to the right). It captures `<name>_drops.png`, `<name>_fp.png` and
`<name>_bag.png`. The hand, the drop and the icon all draw the one model returned by
`VoxelMeshBuilder.itemShape`.

`--outline-probe --screenshot=<png>` builds every species and prints any two parts whose faces
share a plane (the flicker). It builds every species again at every affix size and lists any
model that reaches over its collider's top. Then it aims at a block sunk in the floor, a torch, a
slab, a fence, a door, a flower, a wall torch, a ladder, a sheep and a giant zombie, and prints the
box the aim outline was fitted to for each. The player then walks into a three-high ladder with
jump held; the probe prints how close to the wall the rungs stop it and how high it climbed. It
writes `<name>_block.png`, `<name>_torch.png`, `<name>_ladder.png`, `<name>_mob.png` and
`<name>_giant.png`.

`--anim-probe --screenshot=<png>` clears a long stone pad and measures what the creatures'
limbs actually do: a flying parrot's wings against a standing chicken's folded ones and the
same chicken's while it falls, every walker's legs while it walks and once it has stopped, a
slime's stretch in the air and its splat on landing, the camera's sway on foot against its sway
in the saddle in both views and at a gallop, the player's arms and legs in fly mode (a
stride, never the glide's spread arms), and a backward dodge dash (how far it went, which way
the body faced, the lean, the arms, the hop). It writes `<name>_wings.png` (wings out
beside wings folded), `<name>_walk.png` (a horse from behind, mid-trot, its tail clear of
the barrel) and `<name>_dash.png` (a dash to the right, from the side), and prints every
figure, so none of it has to be read off the pictures.

`--move-probe` walks a cleared pad and prints what the body does at every obstacle: a half step
(a slab) is hopped, a whole block is jumped, a three-block wall is not climbed until the climb
setting is on, a bank is left on the first try, a puddle is waded through without the liquid
state chattering, and the view bobs walking and holds still standing. It then walks a staircase
of three whole blocks twice — once with a cow on its own legs, once with a horse carrying the
player — and prints the largest rise either made in one tick, which is what tells a jump (a few
centimetres) from the lift this used to be (a whole block). Last the horse crosses a pool four
blocks deep and the probe counts the ticks it spent swimming, the ticks it stood on anything
(none) and how deep it rode, which is how walking on water would show.

`--reach-probe` puts a zombie two metres from the crosshair with a stone wall between the two.
It prints what the crosshair holds (the block, never the creature), whether mining runs, and the
damage a swing does through the wall (none); then breaks the wall and swings again. It walls the
zombie off and watches it for three seconds — it may not bite through the wall — and takes the
wall away, when it does. Last it mounts a horse and mines a block from the saddle.

`--map-probe --screenshot=<png>` walks with the corner map on and captures it five times
(`<name>_1.png` … `_5.png`), then switches to the full map (`<name>_full.png`, where the corner
must be gone). It prints how far the ground slid under the arrow between captures and what
keeping the map fresh costs a frame.

`--model-probe --screenshot=<png>` clears a stone pad and captures three poses and a zombie,
and writes two more beside the file: `<name>_hold.png`, a model holding a block side on (the
block must hang off the fist, never run through the forearm), and `<name>_ride.png`, a model
seated on a horse through `Player.saddlePosition` (the legs must be inside the barrel). It
prints the horse's back height and the rider's feet and hips, so the seat can be checked
without reading the picture.

Stage 33 probes: `--new --playground --slot=probe33 --seed=42 --frames=300 --settle=10 --no-tutorial
--screenshot=<png> [--shot=aerial|hub|blocks|building|redstone|rails|water|farm|arena|caves|underwater|arena_inside|hall|steps]
[--shots=a,b,...] [--pg-checks]` waits for the nine exhibits and prints what they hold (zones, block
edits, exhibit mobs, villagers, pets, carts, boats, chests, waypoints, the tour, the kit, the plaza
floor), `--shots=` captures one `<png stem>_<shot>.png` per view in the same run, and `--pg-checks`
drives the shapes' cells, a boss plate, the refill button, F7 / F8, F9 on a broken cottage wall and
the save. A second boot with `--slot=probe33 --playground` (no `--new`) reads the exhibits back
(`edits=0`); `--title-probe --open-playground` captures the title panel. Delete the slot after.

Stage 31 probe: `--new --seed=42 --frames=300 --settle=10 --stage31 --screenshot=<png>` builds a
torch-lit room, a pit with an overhang and an S maze east of spawn, then prints the sky / block
light at the room centre, under the overhang and outside, the room going dark after the torch
is removed (the 3x3 ring remesh), the AO vertex count, the spawn gate dark / lit, a zombie
through the maze on A* against the straight-chase control, and the mesher's own clock (add
`--no-light` to skip both light BFS for the cost comparison). Captures: `--shot=room --time=0.0`
(inside the room at night) · `--shot=cave` (the pit's mouth by day).

Stage 32 probe: `--new --seed=42 --frames=300 --settle=10 --stage32 --screenshot=<png>` builds a
stone pad across the border between the spawn chunk's east neighbour and the chunk west of it,
then prints a torch's block light on the far side of the seam (and the mesher's clock), the
knockback / flash / hit-stop of a swing and the shake / vignette / flash of the player's hit, the
crit count over 200 swings, the crack overlay at progress 0.5 and the break burst with its family
voice, the footsteps over a 5 m walk, the daylight rule for a zombie in the sun, under a roof and
in a pool, the topple-and-fade death clock, and two merged apple toasts with the low-HP pulse.
Captures: `--shot=combat` (a zombie mid-knockback, the flashes, the numbers and the red vignette)
· `--shot=mining` (cracks and chips on a raised stone block, first person).

### The terrain shader (stage 31)

The lit terrain draws with the kit's shader, `voxel_scene`'s `shaders/terrain.frag`:
flutter_scene's standard lit fragment shader with the voxel light term folded into the albedo
(`TerrainMaterial`, `packages/voxel_game/packages/voxel_scene/lib/src/terrain_material.dart`).
It is compiled by hand into that package's `assets/shaders/terrain.shaderbundle` (committed, a
plain pubspec asset; there is no build hook):

```bash
cd packages/voxel_game/packages/voxel_scene
dart tool/build_shaders.dart   # after editing shaders/*.frag, and after every Flutter upgrade
```

The script runs the SDK's `bin/cache/artifacts/engine/darwin-x64/impellerc` (an arm64 binary on
Apple silicon) with the arguments flutter_gpu_shaders' hook uses, `--gles-language-version=300`
(without it spirv_cross aborts on the lighting code) and flutter_scene's `shaders/` on the
include path. A bundle is tied to the engine that compiled it: a stale one fails at boot with
a message naming the script.

Saves live in `~/Library/Application Support/com.example.voxelGameMinecraft/voxel_game_minecraft/worlds/<name>/`
(`world.json` from the New World form, `blocks.bin` edit delta + `player.json`, the same bytes
as the Godot POC). F2 writes a screenshot next to them.

## Starting the game

The game boots into the **title screen** (stage 30): a slowly orbiting voxel vista behind
**Play**, **Multiplayer**, **Settings**, **Credits** and **Quit**. A probe boot (`--new`,
`--slot=`, `--seed=`, `--continue`, `--screenshot=`, `--host`, `--join=`) skips it and lands in
the world as before; `--title-probe` forces the title even then.

- **Play** lists your worlds (`worlds/<slot>/`): name, mode, class, seed, dimension, play time
  and last played. Select one and **Play** (or double-click), **Rename** it, or **Delete** it
  (asks first). **New world** opens the form: a name, a seed (a number, any text — hashed —, or
  empty for a random one), **Survival** or **Creative**, and the class; **Start** creates the
  slot and boots it.
- **Playground** (stage 33) builds a new creative world on seed 42 made to show every feature at
  once (pick a class, then *Build a new playground*). The generator flattens a 144 x 144 grass
  plaza around the spawn (no caves, trees or structures on it) and nine exhibits are laid on it
  in a 3 x 3 grid, each built the first time its chunks load and kept by the save: the **hub**
  (a glider tower, chests holding every item, the crafting stations, the tour waypoint), the
  **block gallery** (every block on a pedestal, the liquids in glass tanks), **shapes &
  building** (a cottage with a stairs roof, stairs, half steps, one-block steps for the auto-jump,
  a climbing wall, a ladder wall, fences, wooden and iron doors), **redstone** (levers, buttons,
  a plate, lamps, an iron door, the 15-wire range, TNT, a piston, a lamp row), **rails** (a loop
  with a hill and a powered stretch, a riding cart, a chest cart), **water, lava & portal** (a
  6-deep pool with a waterfall, a boat, a dock and a sunken chest, a lava basin behind a
  cobblestone gate holding back water, a lit portal to the Underworld), **farm & animals**
  (wheat at every stage, four pens, a tamed horse, wolf and parrot, two villager stalls), the
  **monster arena** (14 monsters and elites behind an iron door, a spawner block, six pressure
  plates that summon the Boomer, Cave Troll, Yeti, Scorpion King, Mummy King or Underworld Lord,
  a gold button that refills the arena) and **light & mining** (every light source in a dark
  hall, an ore wall, falling sand and gravel, a ladder shaft to a diamond chamber at y 12).
  Walking into an exhibit shows its card; the crosshair names the aimed block. The hub's
  waypoint (J, Waypoints) is a **world tour**: the nearest dungeon, tower, camp, village, ruin,
  well, mine and temple, and the nearest forest, desert, snow, mountains, swamp, jungle and
  ocean. Keys: **F7** weather, **F8** time of day (noon, sunset, midnight, sunrise), **F9**
  rebuilds the exhibit you stand in (its creatures, carts and boat too). The zoo and arena
  creatures come back on every boot; the spawner neither despawns nor counts them. Nothing runs
  out in there: stamina and mana are endless, so sprints, dodges and both class abilities can be
  tried one after the other.
- **Creative** worlds take no damage, never get hungry, place blocks without spending them and
  fly with **F5** (Space up, Ctrl down). Survival keeps its feet on the ground.
- **Tutorial**: a new world made from the title shows a card at the top of the screen with the
  next thing to do and the key for it — walk, look, jump, break a block, open the bag (E), craft
  a pickaxe, place a block, eat (H), sleep (or last until sunrise), open the journal (J). Each
  step completes when you do it; the card's button or **F6** skips the rest. Done once, it stays
  done (`settings.cfg`; the Settings screen can re-arm it). `--no-tutorial` keeps a probe quiet.
- **Multiplayer** hosts one of your worlds on port 7777 or joins an address with a class.
- **Settings** is the same panel as the pause menu; **Credits** scrolls the engine, the fonts,
  the audio and every stage of `ROADMAP.md` (bundled as an asset, read at runtime; Esc closes).
- **Esc** in-game: settings, a **Stats** block (play time, metres walked, blocks broken and
  placed, mobs killed, deaths, dimension trips), save, **Save & back to title** (solo), quit.

| Key | |
|:---|:---|
| WASD / Space / Shift / Ctrl | move / jump / sprint / sneak |
| Title → Multiplayer | **Host** opens port 7777 on the selected world; type an address and **Join** to play in someone's world |
| F | board or leave a boat (place one with the Boat item on water); on a villager: the trade screen (three offers, click a row; gold ingots are the coin, sell wheat or melon slices to earn them; Esc / F closes) |
| Mouse | look (third person orbit; the pointer is locked with `pointer_lock`, Esc opens the pause menu and releases it) · LMB attack or mine (hold to keep firing a bow or staff) · RMB place or use · RMB with a bow = fan shot, with a staff = arc |
| Portal | Lava touched by water turns to obsidian (a diamond pickaxe mines it). Build a frame 4 wide and 5 tall with a 2 x 3 hole, aim a Flint and Steel (iron + flint) inside it, and stand in the purple glow for two seconds: you arrive in the **Underworld** — hellstone caverns over a lava sea, soul sand that slows you, glowstone, quartz, blazes, wither skeletons and magma cubes, and somewhere a nether-brick **fortress** whose throne room holds the Underworld Lord and, once he falls, the core that gives up the Underworld Heart. A return portal waits where you arrive. No sun, no weather, no sleeping, and water hisses away down there. In multiplayer everyone in the same dimension sees each other, a different dimension is invisible, and mobs exist only where the host is |
| RMB on a lever / button / door | flips the lever, presses the button (1 s), opens a wooden door; an iron door only opens when powered — wires carry power 15 cells from a lever, button or pressure plate to lamps, iron doors, pistons and TNT |
| Rails | RMB with a Rail (6 iron + stick = 16) lays it turned toward the rails beside it — straight, corner, or a slope when the next rail is a block higher; a Powered Rail (6 gold + stick + redstone dust = 6) speeds a cart up while a lever, button or wire powers it and brakes it when nothing does. RMB with a Minecart (5 iron) on a rail sets it down; F within 2 m sits in it, W / S push it, F gets off; hit an empty cart to pick it up. A Chest Minecart (minecart + chest) carries 36 slots — F opens them (host / solo only). Every abandoned mine has a rail down its corridor and a chest cart of loot at the end |
| 1-9, wheel | hotbar |
| E / Tab | inventory + crafting |
| Q / H / F / V / G / R | drop · eat · interact · first/third person · glider · class ability |
| F1 / F2 / F5 | debug text · screenshot · fly mode |
| F7 / F8 / F9 | Playground only: cycle the weather · cycle the time of day · rebuild the exhibit you stand in |
| M | the map in the top-right corner, centred on you; again: the same map full screen, with markers (waypoints, structures, mounts, spawn) and the corner hidden; again: off |
| Alt | dodge dash: a quick leap where you are walking (backward too), arms thrown back, invulnerable for 0.4 s |
| Riding | On a horse you work the world exactly as on foot: the same crosshair, the same swing, the same mining and placing. Steps are jumped, never teleported up — that goes for every creature, ridden or not — and deep water is swum, not walked on |
| Reach | Whatever is nearest along your line is what you act on. A creature behind a block is out of reach until the block is gone, and the creature's own bite obeys the same rule. Grass, a flower and the gap between two fence posts are not in the way |
| Woods | Trees stand one to a seven-block patch of ground, so two trunks are never closer than five blocks and you walk between them. The trunks are tall (an oak 9-12 blocks, a forest giant and a jungle giant 14-24 on a 2x2 trunk) and the crowns start well over your head. Every biome grows its own: oaks and giants in the forest, lone oaks on the plains, spruces in the snow and the mountains, willows over the swamp, vined giants in the jungle, and palms on the sand of the beaches and the oases. A tree is drawn whole before it is written, and only the part of it that a walk over the six faces reaches from the stump is kept: no leaf floats, no branch hangs off a corner, and nothing roots in the water or where a village, a tower or a camp is about to be built |
| J | journal: talents, bestiary, achievements, waypoints, quests |
| Esc | menu: render distance, mouse, FOV, master and music volume, weather, FPS overlay (saved in `settings.cfg` beside `worlds/`), save & quit — the world keeps running behind it |

## What the port taught (the case study for `dev`)

- **Measured against the Godot POC** in `docs/PERFORMANCE_VS_GODOT_2026-09-11.md`: the
  Dart mesher on isolates matches C# once the pool uses the cores; rendering is the gap
  (Godot holds 120 fps at 2.3 M faces, `flutter_scene` falls to 70 at 2.2 M).
- **`flutter_scene` carries the whole rendering stack** the Godot POC leaned on: vertex
  colours through `MeshGeometry.fromArrays`, a `GradientSkySource` that doubles as the
  `SunLight` with cascaded shadows, exponential-squared distance fog in the horizon colour, only at the edge, ACES tone
  mapping, `PointLightComponent` for the held torch. 225 chunks / ~300k faces render at 60
  fps on an M-series Mac in a debug build.
- **Isolates replace `WorkerThreadPool`.** Generation and meshing are pure Dart on three
  isolates; results cross as `TransferableTypedData`. The first 13×13 window fills in about
  1 s. `FastNoiseLite` from `flutter_scene/noise.dart` is the same algorithm family as
  Godot's (OpenSimplex2S, fBm, ridged), so the biome recipe ported unchanged.
- **Front faces wind counter-clockwise** in `flutter_scene` (glTF), clockwise in Godot: every
  quad's diagonals are mirrored in the mesher and the voxel builder.
- **Flutter has no pointer lock**; `pointer_lock` (macOS) supplies relative deltas drained
  once per fixed step, which is exactly the shape `InputHelper` would want.
- **A camera collision *ray* is not enough here.** The orbit eye sits off the ray (a
  shoulder across and a hand up), it carries a near plane around it rather than being a
  point, and the jolt and the sway move it after the fact — so the eye ends up a few
  centimetres inside a wall, and a wall from the inside is not drawn at all, so every cave
  behind it shows through. `Player.clearDistance` sweeps a 0.25 m box along the exact
  segment the eye will travel and comes in at once instead of easing; the model hides when
  the eye is pulled inside it (`camDistance < 1.1`).
- **The Flutter tool's build-hook runner rejects symlinks** under the package root
  (`hooks_runner` `wrapLink` → `UnimplementedError`) and the macOS SwiftPM plugin links
  live there, so this project has no app-level `hook/build.dart`: `flutter_scene` compiles
  its own shaders with its own hook, and the game has no asset pipeline to run.
- **Screenshots come from a `RepaintBoundary`** around the `SceneView` + HUD + overlays,
  captured after `endOfFrame` (capturing inside the tick trips `debugNeedsPaint`).

# Multiplayer

```bash
cd examples/voxel_game_minecraft
flutter build macos --debug
B=build/macos/Build/Products/Debug/voxel_game_minecraft.app/Contents/MacOS/voxel_game_minecraft
$B --host & sleep 4; $B --join=127.0.0.1
```