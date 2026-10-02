# voxel_game

A Minecraft-like game in a few lines. You declare the blocks, the world,
the player and the creatures in one `VoxelGameSpec` and call
`runVoxelGame`. You get a playable 3D world: mining and placing, an
inventory and crafting, day and night, creatures with goals, saves and
multiplayer.

It is the kit over `voxel_engine`, `voxel_scene` and `sound_recipes`, and it
re-exports what a game needs, so a game imports only this library.

> **Status: 0.3.0-dev**, beta. The API can still change.

## The four packages

`voxel_game` sits on three packages, released from the same repository:

```
voxel_engine    pure Dart        core · worldgen · content · signals · net
voxel_scene     flutter_scene    chunk views, terrain material, rigs, outlines, sky   → voxel_engine
sound_recipes   flutter_soloud   sounds synthesised from recipes, no audio files      → (nothing of ours)
voxel_game      Flutter          VoxelGameSpec, loop, input, player, cameras, mobs,   → all three
                                 spawns, drops, HUD, save, host / join
```

A game needs only `voxel_game`. The other three are there for a game that wants less:
`voxel_engine` alone runs a world with no screen (a server, a test, a worker isolate).

## Features

- `VoxelGameSpec`: blocks, items, recipes, status effects, world, player, mobs, vehicles,
  fishing, sky, sounds, circuits, liquids, screens.
- Survival, declared: `PlayerSpec.hunger` (a `HungerSpec`: the bar empties, a full one heals,
  an empty one starves), `PlayerSpec.xp` (an `XpSpec` curve; `PlayerEntity.gainXp`), food
  (`ItemType(food: Food(hunger: 4, heal: 2, effect: 'regeneration', seconds: 8))`, eaten with
  use) and armour (`ItemType(armor: Armor('chest', 3))`, put on with use, turning a blow aside
  down to `PlayerSpec.armorFloor`). The player carries the spec's `effects` in
  `PlayerEntity.effects`, which bend its speed, damage, mining and armour. Each is off until
  declared, and the default HUD draws only what is: hunger beside the hearts, armour over
  them, the experience bar under them, the effects with their time left at the top left.
- Items have a shape: one voxel model each (`VoxelGame.itemModel`), the same in the
  first-person hand (swaying with the walk, thrown across the screen on a swing), in a
  humanoid's fist in third person and in every other player's, lying on the ground, and as
  its icon in the hotbar and the bag (`ItemIcon`). An item's block, tool, food, armour or
  bucket picks it, or the item declares one (`ItemType(shape: ItemShape.cap)`, or a
  `CustomItemShape` of its own voxels).
- Weather, declared: `SkySpec(weather: WeatherSpec())` rolls clear, rain or a storm every
  few minutes (`WeatherOdds`, or a biome's own in `WeatherSpec.biomes`), eased in; rain and
  storms grey the sky and pull the fog in, a storm strikes with lightning and thunder, and
  what falls is the biome's (`Biome(precipitation: Precipitation.snow)`, or `none` for a
  desert). `VoxelGame.weather` tells what it is and `set`s a spell from code; the player's
  `GameSettings.weather` turns it off. Only a lone game or a host rolls it; a client follows
  the host's sky (`Weather.follow`) and strikes on its own clock.
- A world dressed by rows: `WorldGenSpec(strata: [Stratum('dark_stone', belowY: 22)])`,
  a biome's `covers` (`Cover('snow', minHeight: 101)`), `pools` (`Pools(bed: 'mud')`), trees
  by `weight`, plants that stand `maxHeight` tall, `spread` into patches or grow `byWater`;
  and structures from a stock library built of the game's blocks by name —
  `StructureSpec('village', Village(floor: 'cobblestone', walls: 'planks', ...))`, `Dungeon`,
  `Tower`, `Well`, `Camp`, `Ruins`, `Mine` — or a `CustomStructure` of its own.
- Dimensions and portals, declared: `VoxelGameSpec.dimensions: {'underworld':
  WorldGenSpec(cavern: CavernSpec(), ...)}` gives a game more worlds than its `world`, each
  from the same seed, one streaming at a time, every dimension's edits, crops and stores
  kept for when the player comes back. `PortalSpec(frame: 'obsidian', portal: 'portal',
  lighter: 'flint_and_steel', to: 'underworld')`: the lighter, used on the hollow of a closed
  frame, fills it with portal blocks; standing in them takes the player across, to the same
  column, on firm ground (a pocket carved where there is none), with a portal built there
  for the way back unless one is near. `VoxelGame.travel('underworld')` goes from code, and
  a death elsewhere respawns in the main world. The save and the network carry the
  dimension.
- Circuits, declared by block name: `SignalSpec(wire: ('wire', 'wire_lit'), levers: {'lever':
  'lever_on'}, ...)` — levers, buttons, plates and sources power a wire, and what it touches
  answers: lamps light, iron doors open, TNT blows, `pistons` (`{'piston': 'piston_out', ...}`)
  push the block in front of them the way their `Facing.compass` points, and a run of
  `poweredRails` lights `railReach` rails on from the power. A use flips a lever or presses a
  button (`VoxelGame.useSignal`); on a client the flip is a block edit, which the host's
  circuits answer.
- `VoxelGame.notify('Night falls')` tells the player something for a few seconds; the default
  HUD shows it at the right, over what the player just picked up (`+5 Dirt`).
- The default HUD also reads the world through the frame's camera (`VoxelGame.camera`, the
  one the scene draws with, so `worldToScreen` lands where the scene does): a bar over each
  creature hurt in the last few seconds or under the crosshair, and each hit's damage rising
  over it (`VoxelGame.damageNumbers`). The crosshair turns red on a creature in reach, a ring
  around it fills as a block is mined, a worn tool shows what is left of it under its slot,
  the screen takes the colour of the liquid the camera is in (`LiquidSpec(tint: 0.25)`), a
  `MobSpec(boss: true)` that lives puts its health at the top, and the player's
  `GameSettings.showFps` the frame rate at the top left.
- Blocks that do things, each a field of its row: sand `falls` to where it lands, a torch
  with a `support` drops once its floor or wall goes and is never placed where it would not
  stand, a torch put against a wall becomes its `onWall` form, a block with `loot` drops
  what its `LootTable` rolls, stairs take the `facing` variant the player looks toward, and
  a door is `tall` (two cells, broken as one) and turns into its `usedInto` on a press of
  use. A bucket (`ItemType(bucket: Bucket.empty({'water': 'water_bucket'}))`) scoops a
  liquid's source and a full one (`Bucket.full('water', empties: 'bucket')`) pours it, for
  the flow to spread. A tool works the block it is used on (`turnsWith: {'hoe':
  'farmland'}`), and a crop placed in the world `grows` (`Growth('wheat_1', seconds: 40)`)
  stage by stage while its cell has light. A block with a `storage` (a chest) opens beside
  the bag on use, keeps what is put in it in the world save, and spills it when it breaks;
  one the world generated is found filled from `Storage.loot`, the same for every player.
  The host runs them (`VoxelGame.blockRules`); a client receives what they changed, and
  opens the host's stores where the host is (`VoxelGame.storesHere`).
- Screens as one state machine: `VoxelGame.screen` holds the `GameScreen` open, or null
  while playing — the bag (`BagScreen`, crafting in the hand or at a station), a store beside
  it (`StorageScreen`), the game menu (`PauseScreen`: resume, settings, your screens, quit),
  the settings (`SettingsScreen`, back to the menu), the death
  screen (`DeathScreen`, left only by a respawn: its button, or jump) and your own
  (`DeclaredScreen('journal')`, built by `VoxelGameSpec.screens: {'journal':
  ScreenSpec(buildJournal, menu: 'Journal')}`). `openScreen`, `closeScreen` and `respawn`
  change it and refuse what cannot be. A screen gates the controls, never the world: the
  game keeps stepping behind every one.
- The player's settings (`GameSettings`): render distance, look speed (mouse, finger and
  stick alike), field of view, volume, music volume, view bobbing and the frame rate. The
  spec's values are the defaults (`renderDistance`, `PlayerSpec.fov`,
  `SoundSpec.musicVolume`); `VoxelGame.applySettings` puts a change in force at once — the
  world streams further or is cut back on the spot — and `VoxelGameWidget` keeps them in
  `settings.json` beside `worlds` (`SettingsStore`). `SettingsPanel` is the rows alone, for
  a screen with no game running.
- Worlds and a title (opt-in): `runVoxelGame(spec, menu: TitleSpec(name: 'My game'))`
  opens on a title (`TitleScreen`) instead of in a world — Play lists the worlds
  (`WorldList`: make one from a name, a seed of any text and survival or creative; play,
  rename, delete), Multiplayer hosts one of them or joins an address, Settings sets the
  player's settings with no game running, Credits rolls `TitleSpec.credits`, and Quit
  closes the app on a desktop. The game menu's Quit saves and comes back to it. Each world
  keeps a `world.json` (`WorldInfo`: name, seed, mode, made, last played, play time) beside
  its save; `WorldSaves.create` / `rename` / `worlds` read and write it, and a save from
  before it still loads.
- The bag (`InventoryScreen`): a click or a tap picks a stack up or puts it down, a
  right-click or a long press takes half or leaves one; the held stack follows the pointer
  (above a finger), a tooltip reads the item's row (tool and tier, damage, uses left, food,
  armour, the block it places), a store's slots sit beside the bag, and a stack let go
  outside the panel is thrown into the world. The panel shrinks to fit a phone.
- `runVoxelGame` / `VoxelGameWidget`: the 3D view, a HUD, the inventory and crafting screen.
  A HUD of your own is built once; its pieces follow the game through `HudSelector`s.
  The default HUD's hotbar takes a finger: tap a slot to pick it, hold the one in hand to
  drop one, and `⋯` opens the bag. A HUD is hit-tested like any widget: a piece that takes a
  finger claims it (`InputMap.claimTouch`), a piece that only shows sits in an `IgnorePointer`.
  A loading screen (`LoadingScreen`, or your own `LoadingBuilder`) covers the game until the
  world around the player has filled and the renderer has compiled what it draws.
  Once loaded, the widget shows a `GameSurface`: the world, the touch controls, the HUD and
  the open screen under the one `Listener` that feeds the input. It is public, so a test (or
  a game that draws the world its own way) can mount the kit's wiring over any widget.
- Controls for keyboard and mouse, gamepad and touch; first and third person. A finger on
  the world is a gesture: lift in place to use (or swing), stay put to mine, drag to look.
  A phone also gets `TouchControls`: a floating stick in the lower-left zone (pushed to the
  rim it runs), jump and a sneak switch at the bottom right, the view and pause at the top
  right. They show only while the last device was a finger (`InputMap.lastDevice`), so a
  keyboard or a pad takes them off the screen and a touch puts them back. Lay them out with
  `VoxelGameSpec.touchControls` (a `TouchControlsSpec`), or set it to null for a game that
  draws its own; `TouchControls` is public, and `InputMap.touchMove` / `setTouchHeld` /
  `touchToggle` / `touchPress` / `touchDigit` / `claimTouch` are what any control writes,
  read by the game as the same actions a key presses.
- `MobSpec` with a `Rig` (humanoid, quadruped, bird, blob), a `Gait` and a brain of goals:
  `Wander`, `Hunt`, `MeleeAttack`, `RangedAttack`, `FleeWhenHurt`, `Explode`, `LookAtPlayer`, or `Behavior.custom`.
- `Goal` / `GoalSelector`: the same goal system for your own creature classes.
- A creature drops a `LootTable` and is worth `xp`; it can grow with the player
  (`MobLevels`), burn by day (`burnsInDaylight`), split when it dies (`MobSplit`) and leave
  an effect with its strike (`HitEffect`).
- Taming (`tameWith`, `tameChance`, `tamedBrain`): companions that `PetFight` and `Heel`,
  and mounts (`MountSpec`, `MountWait`) the owner rides with a use and leaves with sneak.
  A tamed creature, and one declared `persistent`, is never despawned and is kept in the
  save; a `ghost` flies through walls, drawn see-through.
- Vehicles, declared: `VoxelGameSpec.vehicles: [BoatSpec(item: 'boat'), CartSpec(item:
  'minecart')]`. The boat's item, used, puts it on the water along the aim; a use on it
  gets in, the move keys row and steer it, sneak gets out, and a swing breaks it back into
  its item. The minecart goes on a rail and rides the rails: rails lay themselves into
  straights, curves and slopes as they are placed (`Rails`), a cart rolls down a slope,
  a powered rail on speeds it and one off brakes it, and its rider pushes it along with the
  move keys. A mount and a vehicle are both `Rideable` (`PlayerEntity.ride` / `riding` /
  `dismount`). A vehicle stays where it was left, in the save and across a trip to another
  dimension.
- Fishing, declared: `VoxelGameSpec.fishing: FishingSpec(rod: 'fishing_rod', catches:
  LootTable.oneOf([...]))`. The rod casts a float at water; after a few seconds something
  bites, and a use within the bite lands one catch in the bag and some experience.
- Combat that is felt: a blow holds its victim's pose for a moment (the hit-stop), shows it
  white and shakes it, and its shove carries it off its feet; the player's camera shakes by
  the damage taken. A creature dies by toppling over and fading out. `PlayerSpec.critChance`
  makes some of the player's blows critical (`critMultiplier`, the number yellow with a `!`).
  A creature set alight (`Mob.ignite`) burns orange and sheds embers. Blocks chip as they are
  mined and burst as they break (`VoxelGame.debris`, one particle system).
- `ProjectileSpec` for `RangedAttack` and `VoxelGame.shoot`: an `arrow`, a `bolt` and a
  `fireball`, or your own; a shot can carry a `light`, leave a `trail`, set the creature it
  hits burning (`burns`) and leave an effect on the player (`onHit`).
- `SpawnRule.daylight()` / `SpawnRule.dark()` / `SpawnRule.cave()`, on the surface or in
  caves (`SpawnPlace`), weighted by biome (`biomeWeights`).
- Save slots, and `hostPort` / `join` for multiplayer.
- Hooks: `onBlockBroken`, `onBlockPlaced`, `onMobKilled`, `onTick`, and `GameSystem`s.
- `GraphicsSpec`: render scale, a pixel-ratio cap, anti-aliasing and the sun's shadows, with
  a `desktop` and a `phone` preset (the phone's is picked on iOS and Android).
- `VoxelGame.stats`: an FPS readout, and per-frame samples (UI, raster, simulation, scene
  encoding, GPU latency) for a benchmark.

## Install

```yaml
dependencies:
  voxel_game: ^0.3.0-dev
```

To work against a checkout of the repository instead, override all four packages by
path — a plain `path:` on `voxel_game` alone does not resolve, because it still asks for
the other three from pub.dev:

```yaml
dependency_overrides:
  voxel_game:    {path: ../voxel_game/packages/voxel_game}
  voxel_engine:  {path: ../voxel_game/packages/voxel_engine}
  voxel_scene:   {path: ../voxel_game/packages/voxel_scene}
  sound_recipes: {path: ../voxel_game/packages/sound_recipes}
```

Dart SDK `^3.13.0`.

- **Flutter 3.47.1 or later**, with Flutter GPU turned on in each runner: `flutter_scene`
  draws through it, and it is off by default.

  | Platform | File | Add |
  |:---|:---|:---|
  | macOS, iOS | `macos/Runner/Info.plist`, `ios/Runner/Info.plist` | `<key>FLTEnableFlutterGPU</key><true/>` |
  | Android | `android/app/src/main/AndroidManifest.xml`, in `<application>` | `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />` |
  | Windows | `windows/runner/main.cpp`, after `flutter::DartProject project(L"data");` | `project.set_enable_flutter_gpu(true);` |
  | Linux | `linux/runner/my_application.cc`, after `fl_dart_project_new()` | `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` |

  The Windows and Linux settings first shipped in Flutter 3.47.1; before it only the
  `--enable-flutter-gpu` flag turns Flutter GPU on, and release builds ignore it.
  macOS and Android are measured (`example/`); the example's iOS, Windows and Linux
  runners are set up but have not been run yet. On Windows and Linux the mouse look is a
  drag, not a locked cursor: `pointer_lock` locks it only on macOS.
- **Not the web.** Chunks are generated on worker isolates, multiplayer is TCP sockets and
  saves are files, through `dart:isolate` and `dart:io`, which a browser does not have.
  (`flutter_scene` itself runs on the web; the kit does not.)

- **Landscape on a phone.** `runVoxelGame` locks a phone or tablet to the two landscape
  orientations; declare the same in the runners so the launch screen is not upright:
  `android:screenOrientation="sensorLandscape"` on the activity in
  `android/app/src/main/AndroidManifest.xml`, and in `ios/Runner/Info.plist` only
  `UIInterfaceOrientationLandscapeLeft` / `Right` under both
  `UISupportedInterfaceOrientations` keys, with `<key>UIRequiresFullScreen</key><true/>`.

- For multiplayer on macOS, add the `com.apple.security.network.server` and
  `com.apple.security.network.client` entitlements. On Android, add
  `<uses-permission android:name="android.permission.INTERNET"/>` to
  `android/app/src/main/AndroidManifest.xml`: Flutter's template grants it only to debug
  and profile builds, so a release build cannot host or join.

## Usage

1. **Declare your blocks.** Air is added for you.

   ```dart
   const blocks = [
     BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1),
     BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel'),
     BlockType('grass', color: 0x5C9E3A, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
     BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel'),
   ];
   ```

2. **Declare the world.**

   ```dart
   const world = WorldGenSpec(
     bedrock: 'stone',
     biomes: [Biome('plains', top: 'grass', under: 'dirt')],
     beach: Biome('beach', top: 'sand'),
   );
   ```

3. **Add creatures.** The brain is a list of goals; the lower priority wins.

   ```dart
   const zombie = MobSpec('zombie', hp: 20,
       rig: Rig.humanoid(skin: 0x5E9A5A, armsForward: true),
       brain: [MeleeAttack(damage: 3), Hunt(range: 18), Wander()],
       spawn: SpawnRule.dark());
   ```

4. **Run it.**

   ```dart
   void main() => runVoxelGame(
         const VoxelGameSpec(blocks: blocks, world: world, mobs: [zombie]),
         saveSlot: 'world1',
       );
   ```

5. **Grow it** with `items`, `recipes`, `effects`,
   `player: PlayerSpec(startingItems: {...}, hunger: HungerSpec())`, `sky`, `sounds`,
   `signals`, `graphics`, `screens`, and the `on...` hooks.

6. **Play together (optional):** `runVoxelGame(spec, hostPort: 7777)` on one
   machine and `runVoxelGame(spec, join: '192.168.0.10')` on another. A client's block
   edit shows at once, and the host keeps it only over the block it replaced: of two players
   on one cell, the second is rolled back. The items on the ground are the host's: a
   client's drop is made there, and the host hands each stack to the nearest player whose
   bag takes it. The stores are the host's too: a client's edit of a slot stands only on what
   the slot held, and only with what the client holds, so two players never take one stack.

7. **Open on a title (optional):** `runVoxelGame(spec, menu: TitleSpec(name: 'My game'))`
   lets the player make, pick, host and join worlds instead of dropping into one slot.

## Example

```sh
cd example
flutter run -d macos
```

[`example/lib/main.dart`](example/lib/main.dart) is a small game in one file:
twelve blocks, two biomes with trees and coal, a few recipes, a player with a
pickaxe, sheep by day and zombies by night.

## Working on the kit

The four packages share one repository, [`fluttely/voxel_game`](https://github.com/fluttely/voxel_game);
its root README says how to run the suite, and its `CLAUDE.md` the rules the code is held to.
