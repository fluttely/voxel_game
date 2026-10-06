# Voxel Minecraft — a Minecraft clone on the voxel kit

A Minecraft clone built on this repository's kit (`voxel_game` over `voxel_scene`,
`voxel_engine` and `sound_recipes`), drawn with [`flutter_scene`](https://pub.dev/packages/flutter_scene)
(Flutter GPU / Impeller). The whole game is one `VoxelGameSpec` in `lib/src/spec/` plus the
systems and screens a game adds on top of the kit: classes, a journal, bosses, villages,
waypoints, a map, a playground. The kit runs everything else: the loop, the player, the
creatures, the world and its dimensions, the save, the HUD, the menus, host and join.

It is the kit's largest witness, so it takes the kit from this tree, never from pub.dev:
`pubspec.yaml` overrides the four packages by path. It is not published.

## Running

```bash
cd examples/voxel_game_minecraft
flutter run -d macos          # Flutter GPU is on in macos/Runner/Info.plist
flutter test                  # headless, on the spec; no screen, no audio device
```

macOS is where it is developed; the kit's other targets (iOS, Android, Windows, Linux) have
their runners here too. Not the web: the kit needs `dart:io` and `dart:isolate`.

## Playing

The game opens on its **title**, a meadow orbiting behind **Play**, **Multiplayer**,
**Settings**, **Credits** and, on a desktop, **Quit**.

- **Play** lists your worlds; one can be played, renamed or deleted. **New world** asks for a
  name, a seed (a number, any text, or nothing for a random one), **Survival** or
  **Creative**, and three choices of this game's: the **Class** (warrior, ranger, mage,
  rogue), the **Tutorial** (on or off) and the **Kind** (an open world or a playground).
- **Multiplayer** hosts one of your worlds on port 7777, or joins an address with a class of
  your own. The host's world is the one played; everyone in the same dimension sees each
  other.
- **Settings** has the render distance, the look speed, the field of view, the volume and
  the music's (the meadow's track under the title follows it at once), the view's bobbing, the frame rate on screen and the weather. **Credits**
  rolls what the game is built on and every stage of `ROADMAP.md` (bundled with the app).
- **Esc** in a world opens the game menu: settings, the **Journal**, the **Map**, the
  **Stats**, the **Controls**, and **Playground** in a playground. The world keeps running
  behind every menu. Every menu and screen, the title's included, is worked by a pad (the
  d-pad or the left stick moves, A presses, B goes back) and by the arrows, Enter and Esc.

What the game adds to the kit's Minecraft: four **classes**, each with two powers, a dodge,
stamina, mana and talents bought with levels; a **journal** with quests, achievements, the
creatures met and the waypoints; a **tutorial** card for a player's first steps, shown once per machine; **elites**
(swift, giant, venomous, …) among the creatures; **bosses** in the desert temple, the
dungeon and the underworld's fortress, whose lord seals its core; **villages** whose
villagers trade; **waypoints** to travel between; an **enchanting** table; the **map** and
minimap; and the **playground**.

### The playground

A world of the Playground kind presses a flat plaza around the spawn and lays nine
exhibits on it, each built the first time its chunks load: the **hub** (a glider tower,
chests holding every item, the stations, a waypoint whose list is a world tour of the
nearest structures and biomes), the **block gallery**, **shapes** (stairs, slabs, fences,
doors, ladders), **redstone** (levers, buttons, a plate, lamps, an iron door, TNT, a
piston), **rails** (a loop over a hill with a powered stretch and a cart), **water, lava
and a portal**, the **farm** (crops, pens, villagers, a tamed horse, wolf and parrot), the
**arena** (monsters and elites, a spawner block, six plates that call a boss each, a gold
button that fills it again) and **light and mining**. The player starts at the hub at level
10 with ten talent points and the showcase kit, and nothing runs out there. Walking into an
exhibit shows its card.

### Keys

The **Controls** screen (F1, the pad's Home, or the game menu) shows these in the game.

| | |
|:---|:---|
| **Keyboard and mouse** | W A S D walk · Space jump · Shift run · Ctrl sneak · left click mine and hit · right click place, use, eat, wear · E bag · Q drop · V first or third person · Esc menu · R and F your class's two powers · Alt dodge · J journal · G glide (with a glider in the bag) · F5 fly (in a Creative world) · M the map: small, then big, then gone · F1 controls · F6 skip the tutorial · in a playground: F7 the weather, F8 the time of day, F9 rebuild the exhibit you stand in · on a menu: the arrows move, Enter or Space press, Esc go back |
| **Gamepad** | left stick walk · right stick look · A jump · B sneak · Y bag · right trigger mine and hit · left trigger place and use · bumpers your powers · X dodge · touchpad journal · d-pad: up glide, right fly, down drop, left the next hotbar slot · Start menu · Back the map · Home controls · Tutorial in the menu skips the tutorial · on a menu: the d-pad or the left stick moves, A press, X take half in the bag, B go back |
| **Phone** | the stick at the left walks; drag anywhere else to look · tap to hit or use, hold to mine; the buttons at the right do the rest · the map button cycles the map · the menu button at the top has the journal, the map, the stats and the controls |

### Saves

The kit's: `worlds/<slot>/` (`world.json`, `game.json`, `edits.bin`) under the app's support
folder, with `settings.json` beside `worlds/`. On macOS that is
`~/Library/Application Support/com.example.voxelGameMinecraft/`. The old app's folder there,
`voxel_game_minecraft/`, is read by nothing and can be deleted: its worlds do not load on the
kit (VAD15).

## Lineage

The game began as a file-by-file port of a Godot POC to `flutter_scene`, stage by stage
(`ROADMAP.md`). The kit's packages were extracted from that port (the VP, VK and VC plans in
the repository's `docs/`), and the absorption plan (VA) then grew the kit until the app could
run on it: on 2026-10-04 (VA-Zm) the app's own engine — about 23k lines of game loop,
player, creatures, world, save, HUD and network — was deleted. That code, its probe flags
and its stage tests are in git history before `837d670`. The measurements against Godot are
in `docs/PERFORMANCE_VS_GODOT_2026-09-11.md`.
