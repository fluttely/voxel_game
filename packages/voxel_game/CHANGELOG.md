# Changelog

## Unreleased

- **A game keeps its own settings of the player's (KL-020).** `GameSettings.game` (new):
  JSON under the game's keys, which the kit never reads, written with the rest to
  `settings.json` (version 3; a version 1 or 2 file reads it empty) and kept by
  `copyWith`, the store and the settings screens. It is a copy no one changes: a value that
  is not JSON throws, a change is a `copyWith` put in force by `VoxelGame.applySettings`.
  What holds across worlds (a tutorial seen, a hint read, a layout) no longer has to be a
  world option asked on every new world. `VoxelGame.startHeadless` takes `settings` (new),
  the player's own at its load radius, so a test starts a game where a machine stands.
- **A title plays music of its own (KL-019).** `TitleSpec.music` (new) names one of the
  game's tracks; `TitleScreen` plays it on an audio device it closes as it goes, before a
  world's music starts, and its Settings move the music's volume at once. `GameMusic`
  (new) is what both play through: a `MusicSpec`'s tracks on a `MusicDirector`, at
  `GameSettings.musicGain` (new), following the settings, one music at a time
  (`GameMusic.playing`). A game with music under its title no longer opens a second
  `SoundBank` in its background, copies the mapping, or plays at a volume read once.
  `VoxelGameWidget` keeps its music where the platform has no audio device (silent, as its
  bank), and closes a bank opened after it was disposed.
- **A game says where a new world's player starts (KL-023).** `VoxelGameSpec.spawn` (new),
  beside `playerFor` and `worldFor`: given a world's options, a `SpawnPoint` (new: a column
  and a yaw) or null for the dry column the kit finds by the origin. The player stands
  there, facing it, from before the first frame, and it is their respawn point; a world
  loaded from a save keeps the place it was saved at, and a client its host's. A showroom,
  a lobby or a story's first scene no longer moves the player in a system a step late.
- **A creature derived from another keeps what it does not name (KL-018).** `copyWith`
  (new) on `MobSpec`, `SpawnRule`, `ProjectileSpec` and every behaviour with fields
  (`Wander`, `Hunt`, `MeleeAttack`, `RangedAttack`, `FleeWhenHurt`, `Explode`,
  `LookAtPlayer`, `PetFight`, `Heel`, `MountWait`, each with its `priority`). A field
  that may be null is given as a getter of its new value, as in `VoxelGameSpec.copyWith`:
  `spawn: () => null` asks for none, `name: () => null` goes back to the id's. A variant,
  a difficulty or a test no longer rebuilds a creature field by field, and a field added
  later reaches every creature derived by it.
- **A game's screen listed only where it applies (VA-Zl5).** `ScreenSpec.listed` (new): whether
  the game menu lists the screen in a game (a playground's controls in a playground only),
  every game when null; `ScreenSpec.listedIn` (new) asks it. On a phone the menu is the one
  way to such a screen, so a world that has no use for it no longer shows its button.
- **A world's options shape its world (VA-Zl5).** `VoxelGameSpec.worldFor` (new), beside
  `playerFor`: the main dimension as a world's options make it, a playground's flat `Plaza`
  (new from the engine, re-exported) pressed into it, say; `worldWith` (new) asks it, and
  `WorldInfo.applyTo` plays it. A host's `hello` carries its game's options and a client
  joining generates the world they make (`joinHost`'s `options`, new), so the two grounds
  agree.
- **A trip keeps the creatures the save keeps (KL-021).** `VoxelGame.travel` parks the
  tamed and `persistent` creatures of the dimension left (`Mob.kept`, new) and puts them
  back when the player comes back, as it did the vehicles; only the wild ones are left
  behind for good. `parkedMobs`, `mobRows`, `restoreMobs` and `mobFrom` (new) mirror the
  vehicles' four; `Mob.row` (new) is what is kept of one.
  - `Mob.data` (new): a game's own state on a creature, JSON values the kit never reads,
    kept with it in the save and across a trip.
  - `game.json` is version 9: the creatures of every dimension, each with its `home` and
    its `data`. A version 6–8 save still loads, its creatures at home where they stand,
    with no data.
- **A creature that takes no harm (VA-Zl2).** `MobSpec.invulnerable` (new, off): a blow is
  felt (it flinches, cries and is shoved, `lastHurtBy` set) but takes no health, and
  neither a fire (`Mob.ignite`) nor the daylight burns it. A villager, say.
- **A world's options make its player (VA-Zj).**
  - `VoxelGameSpec.playerFor` (new): the player a game's options make (a class), given the
    declared one; `playerWith(options)` reads it. `WorldInfo.applyTo` plays a world's
    player through it before its mode.
  - `VoxelGame.options` (new): the choices a game plays with, its `worldInfo`'s or, joined,
    the join form's. `start` and `startHeadless` take `options` for a game in no slot (with
    an `info` too, they throw); `joinGame` takes `options` and plays `playerWith` them.
  - `WorldOption.join` (new, off): the join form offers that option too, and `JoinHost`
    carries what it picked (`options`), which `VoxelGameWidget.joinOptions` plays with.
  - A pose carries its game's options (`op`), read as `RemotePlayer.options`; another
    player is drawn with the rig of the player its options make, built again when they
    change, so a class's colours show on every side with no code of the game's.
    Until its first pose says them, a peer is drawn as the declared player.
- **A shot a game pays for (VA-Zj).** `PlayerEntity.shotVetoes` (new): by source, a reason
  refuses the shot of the launcher in hand (told once a hold and at each press, as an
  empty quiver is, and nothing spent); `ShotFired` (new event) is raised for each shot that
  goes, where the game pays for it (a staff's mana).

- **Frame pacing (VA-Zg).**
  - `GraphicsSpec.paced` (new, off in both presets): the world reaches the screen only
    once the GPU has finished drawing it, voxel_scene's `GpuPacedScene`. On Metal a
    Flutter frame held on a busy GPU lets later frames overwrite the glyphs it copies, and
    the menus and the HUD over the world turn to noise; paced, they stay readable, and the
    world shows one frame late, drawn on the vsyncs that find the last frame finished.
    The kit's scene (`MeasuredScene`) is one, and measures only the frames it renders.
  - `GraphicsSpec.copyWith` (new).
  - `VoxelGame.scene` is a `GpuPacedScene` (re-exported; it was a `Scene`), so a game reads
    its `rendered` and `shown`; `VoxelGame.dispose` lets go of the pictures it holds.

- **Net for a game (VA-Zf).**
  - `VoxelGameSpec.messages` (new): a game's own message types → `MessageHandler` (new:
    `(game, from, message)`), called where one arrives, with the sender's peer number (the
    host's is `GameSession.hostPeer`). `GameSession.sendToHost` (a client's),
    `broadcast` (`except:`) and `sendTo` (the host's) send one, wrapped as a `game`
    message; each throws for a type the spec does not declare, and on the wrong side. A
    peer's message of a type neither the kit nor the spec has now throws where it arrives
    (it was dropped), as VAD11 says. `NetMessage` is re-exported.
  - `PlayerEntity.name` and `poseExtras` (new) ride every pose; `RemotePlayer.name` (the
    peer's, or `Player <peer>`) and `extras` (read-only) on every other side, the host
    passing a client's on. `DefaultHud` draws each other player's name over it, alive, in
    the player's dimension and within `DefaultHud.nameRange` (32 m, new).
  - `Damage.effect` (new, a `HitEffect`) and `Damage.withEffect`: a hurt that lands on a
    player leaves it (`PlayerEntity.takeDamage`), whichever side the player is on. A
    creature's `onHit` and a shot's `ProjectileSpec.onHit` go through it, so a peer a
    spider bites is poisoned on its own side (it was only the host's player). The `hurt`
    message carries the effect and the hurt's source (`src`; it was always `melee`
    there), and so does a client's `hit`.
  - A client's shot the host lands on a creature is handed back to its peer
    (`GameSession.landed`, new; a `landed` message), which rolls its own critical and
    runs its own `PlayerEntity.damageOut` as for a swing (the host's player's filters no
    longer apply, and a peer's were never run).
  - The host's blasts are heard on its clients (`GameSession.exploded`, new; a `blast`
    message): a creeper's too, which no client heard. A lit explosive's replica no longer
    sounds at its end; a client's `VoxelGame.explode` throws.
  - **Breaking:** `Mob.stun`, `slow` and `forget` on a replica ask the host
    (`GameSession.stunMob`, `slowMob`, `forgetMob`, new) instead of throwing.
  - `VoxelGame.eyeLiquid`: a pool's top cell holds the eye only under its drawn surface
    (`ChunkMesher.liquidTop`), as the app's did.
  - The example: H waves (an action, a message to the host passed on to the others), and
    the glowstone's blessing rides the pose, named in the wave's notice.
- **Minecraft's world (VA-Ze).**
  - **Breaking:** `SignalSpec.explosives` maps a block to an `Explosive` (new: `radius` 3.5,
    `damage` 18, `fuse` 3.2 s, `chainFuse` 0.5 s, the app's TNT), not a radius. Powered, an
    explosive is lit (`VoxelGame.ignite`, new; the authority's alone): the block goes and a
    `LitExplosive` (new entity) flashes white every 0.4 s where it stood, falling as a body,
    until its fuse runs out and it bursts (`VoxelGame.explode`). A blast lights the
    explosives it reaches on a fuse of `chainFuse` to three times it instead of breaking
    them. The host sends `lit`; a client draws a replica that sounds at its end. A lit one
    is not saved. `VoxelGame.explosives` (new) by block id.
  - `VoxelGameSpec.structureLoot` (new): a structure's name → `StructureLoot` (new: a
    `LootTable` and a `LootBonus`, new: one of its items in `chance` of the stores with an
    `ItemStack.bonus` from `min` to `max`, the app's 45 % and 1..6). A store the world
    generated within a structure's reach is found with it instead of its block's loot,
    seeded by its cell and the world. `VoxelGame.structureAt` (new) is the nearest structure
    whose reach holds a cell. `checkStructureLoot` (new, at start) throws for an unknown
    structure or item, a bonus of nothing, a one-of table over 1. (The loot is the kit's,
    not `StructureSpec`'s: voxel_engine's worldgen may not import its content.)
  - A stack's `bonus` now counts: it adds to a swing's damage and to the shot of the
    launcher holding it (it was only shown).
  - `SkySpec.dimensions` (new): a dimension id → `DimensionSky` (new: a `StillSky` and a
    `Haze`, both voxel_scene's, re-exported); `checkDimensions` throws for an unknown one.
    `VoxelGame.dimensionSky` and `VoxelGame.haze` (new): the frame draws the still sky and
    the haze of the liquid the camera is in, else the dimension's.
  - `LiquidSpec.haze` (new): water's `LiquidSpec.water` (a deep blue, 0.05, following the
    sky) and lava's `LiquidSpec.lava` (orange, 1.2) by default, the app's numbers; null for
    the sky's fog.
  - Re-exported `Flats`, `Temple`, `PlacedStructure`.
  - The example: TNT and a plate (`signals`), a desert temple with its trap and loot, a
    dungeon's loot with a bonus bow, the swamp's flats, a frozen shore, the underworld's
    still sky and red haze. Its world (and the benchmark's) moves on purpose.

- **Minecraft's items (VA-Zd).**
  - A bow: an item with a `Launcher` (voxel_engine) shoots on attack — pressed, or held at
    its cooldown — the `ProjectileSpec` its `shot` names in `VoxelGameSpec.shots` (new),
    from just below the eye, straight where the player looks, falling. One of its `ammo` is
    spent from the bag and the launcher wears (neither in creative); with none the player
    is told. The shot is times `damageMultiplier`, rolled for a critical one, and filtered by
    `PlayerEntity.damageOut` where it lands (`PlayerEntity.dealtTo`, new, what a swing uses
    too); a client's shot that the host lands is not filtered there. A finger's tap with a
    launcher in hand shoots. `VoxelGame.shoot` takes `overDrop` (new; false shoots straight
    on). `VoxelGameSpec.checkShots` (new, run when the game is made) throws for a shot not
    declared, ammo that is no item, a launcher that places a block.
  - A held light: `PlayerEntity.heldLight` (new) is the item in hand's `ItemType.light`; a
    point light in its colour lights the way around the player (`HeldLight`, new), and
    around another player holding one.
  - `Food.cures`: eating it ends the bad effects (boosts stay), and makes a food that would
    do nothing else edible while one is on.
  - Shears: `MiningRules.cuts` cut a block at once and drop the block itself
    (`VoxelGame.breakBlock`). `MobSpec.fleece` (new, `Fleece`: the item, the tool kind, a
    count, a regrow time) is shorn by a use with its tool: `Mob.shear` (new) drops the
    fleece and `Mob.shorn` / `shornLeft` (new) count it back, the body drawn smaller
    meanwhile; a save keeps it. A client asks the host (`GameSession.shearMob`, new, a
    `shear` message; the host's `state` says `sh`).
  - `MobSpec.yields` (new): a use on the creature turns one of the item in hand into
    another (a bucket on a cow is milk).
  - A bed (`BlockType.bed`): a use sets the spawn there, and at night, nothing hunting the
    player, lies down in it (`PlayerEntity.sleeping` / `bed` / `wake`, new; the eye low, the
    model lying). Once every player has slept `VoxelGame.sleepSeconds` (2) the host's clock
    jumps to `VoxelGame.morning`; each sleeper wakes with the day to a `Slept` (new event).
    Jump, sneak, a blow or the bed gone gets them up. A bed sleeps only in the main world.
    `VoxelGame.isNight` (new). A player's pose says it sleeps (`z`), and another player who
    sleeps is drawn lying.
  - `buildItems` leaves out a block that is not `holdable`, and throws for a block whose
    `drop` (itself by default) is no item, and for a block a tool cuts that is no item.
    `breakBlock` no longer skips a drop that is no item. `checkUses` throws for a use on a
    bed, and on a mob that yields or is shorn; `checkMobs` for a yield or fleece of an
    unknown item, a yield for an item that tames, a fleece no tool shears.
  - The example: a bow and 32 arrows, shears that shear the sheep and cut leaves, a bed, a
    cow that is milked, milk that cures; the blocks only the world makes are not holdable.

- **The player's and a creature's numbers from code (VA-Zc).**
  - Use rules: `VoxelGameSpec.blockUses` (block name → `BlockUse`) and `mobUses` (mob id →
    `MobUse`), both new, call a game's handler on a press of use, before the kit's own
    uses: a block's unless the player sneaks (sneaking builds against it), a creature's
    whenever it lives (`PlayerEntity.usableOn` is true for it, so a finger's tap on it
    uses). `VoxelGameSpec.checkUses` (new, run when the game is made) throws for an
    unknown block or mob, a block the kit uses already (a store, a block that turns, a
    lever or button, a station, one a tool works) and a mob that is tamed.
  - `PlayerEntity.boosts` (new, `Boost` by source: speed, damage, mining multipliers,
    armour and most-health points) bend `speedMultiplier`, `damageMultiplier`,
    `miningMultiplier` (new, with the effects' stats), `armor` and `maxHp`; a respawn keeps
    them, the kit does not save them, and health over a lowered `maxHp` comes down to it in
    the step. `damageIn` / `damageOut` (new, `DamageInFilter` / `DamageOutFilter` by
    source) filter a hurt the player takes (before armour; brought to 0 it never lands and
    is not felt) and a blow they deal a creature; a negative result throws.
    `sprintVetoes` (new) stop a sprint on foot and in a saddle, and `sprinting` (new) says
    whether the player sprints this step. `PlayerSpec.grace` (new, the 0.4 s every blow
    leaves) and `PlayerEntity.grantGrace` / `graceLeft` (new) give and read it from code.
  - `Mob.stun(seconds)` (no thinking, no walking; `stunned`), `slow(share, seconds)`
    (`pace`; a second keeps the slower share and the longer time) and `forget()` (drops
    its target and who hurt it), all new; each throws on a replica.
  - `DefaultHud(game, bars: [...])` (new) shows a game's own `HudBar`s (new: a label, a
    colour, a fill 0..1 read every frame) under the hearts, over the experience.
  - The example: stamina that a run spends, a sprint veto when it is spent and its bar in
    the HUD (`hud`); a glowstone is a shrine whose use blesses the player with two more
    hearts for good (a `Boost`, kept by a `SavedSystem`).

- **Events and a game's save (VA-Zb). Breaking:** `VoxelGameSpec.onBlockBroken`,
  `onBlockPlaced`, `onMobKilled` and `onTick` are gone, and `VoxelGameSpec.systems` is a
  factory (`() => [QuestLog()]`, `VoxelGameSpec.noSystems` by default) instead of a list.
  - `GameEvent` (new, sealed): `BlockBroken`, `BlockPlaced`, `MobKilled` (with `byPlayer`),
    `ItemPickedUp`, `ItemCrafted`, `FoodEaten`, `LevelGained` (one a level), `PlayerDied`
    (with the blow), `Travelled`, `Mounted`, `Boarded`, `Tamed`, `Caught`, `ScreenOpened`.
    `VoxelGame.raise` (new) queues one; each step, after the game's own, every system hears
    the events raised since its last turn, in order (`GameSystem.onEvent`), then ticks. A
    load raises none. `PlayerEntity.craft` (new) crafts from the bag and raises
    `ItemCrafted`; the bag screen crafts through it. `PlayerEntity.kill` takes the blow
    (`by`), `VoxelGame.playerDied` takes the cause.
  - `GameSystem` moved to `core/game_system.dart` and is an `abstract mixin class` whose
    `tick` and `onEvent` do nothing until overridden (extend or mix it in; `implements`
    must write both). `VoxelGame.systems` (new) holds the game's own set, made once a game,
    so a second world from the title starts fresh; `VoxelGame.system<T>()` (new) finds one.
  - `SavedSystem` (new): a system that writes `save` under its `saveKey` in `game.json`'s
    `game` and gets it back in `restore` when the world loads. `game.json` is version 8;
    a version 7 save loads with the systems as made, a key no system saves throws, and two
    systems of one key throw when the game is made.
  - `WorldInfo.options` (new): the game's per-world choices, offered in the new-world form
    by `TitleSpec.worldOptions` (new, `WorldOption`s: an id, a label, choices by value; the
    first chosen until another is), shown in the world's row, kept in `world.json` version
    2 (version 1 reads with none), and read by a system as `VoxelGame.worldInfo` (new: the
    slot's `WorldInfo`, null for a game in no slot; `VoxelGame.start` / `startHeadless`
    take `info`). `WorldSaves.create` takes `options`.
  - The example's clock (T) reads the world's `clock` option (24- or 12-hour), and a
    `_Tally` system counts the blocks broken and placed and the creatures felled, kept in
    the world's save.
- **Actions (VA-Za).** A game's own actions, and two of the kit's for flying and gliding.
  - `VoxelGameSpec.actions` (new) of `ActionSpec` (new): an id, the keys and pad buttons that
    press it and the icon of its touch button (optional). `VoxelGame.actions` (new, a
    `GameActions`) reads them from the same keys and pad the kit's `InputMap` records
    (`InputMap.keyDown` / `keyPressed` / `padDown` / `padPressed`, new) and from their
    buttons: `down`, `justPressed`, `hold`, `tap`, cleared after every step as the kit's
    are; `GameSurface` and `VoxelGameWidget` let go of what a button held when a screen
    opens or the pointer is lost. A `GameSystem` reads them in the step, while `gameplay`.
  - `ScreenSpec.action` (new): a game's action that opens its screen while the player plays
    and closes it again (as the bag's key does); pause still closes it.
  - `VoxelGameSpec.bindings` (new, `VoxelAction.defaultBindings` by default) and
    `InputBindings.rebind` (new): a game moves a kit action to another key or pad button,
    or off one it wants. `VoxelGameSpec.checkActions` (new, run when the game is made)
    throws for two actions of one id, a key or button that presses two actions (two of the
    game's, or one of the game's and one of the kit's) and a screen opened by an action not
    declared or one that opens another.
  - `VoxelAction.fly` (new, F, dpad right): in creative, takes off and lands
    (`PlayerEntity.flying`, new; setting it on throws for a player who is not creative, is
    dead or rides). A flyer has no gravity and no fall, rises with jump, sinks with sneak,
    and moves at `PlayerSpec.flySpeed` (new, 11.5), a run faster by as much as it walks
    faster. Riding and dying land it.
  - `VoxelAction.glide` (new, G, dpad up): held in the air with an item that glides in the
    bag (`ItemType.glider`, voxel_engine), the fall is capped at the glider's sink, the body
    sails toward the look (steered by the move) at its speed, and the landing never hurts.
    `PlayerEntity.glider` (new) is the first glider in the bag, `PlayerEntity.gliding` (new)
    whether it glided this step. `CharacterMotor.step` takes `glideFall` (new), a glider's
    own cap for the step. `RigInstance.animate` and `RigAnimator.pose` take `gliding`
    (new): a humanoid spreads its arms (`RigAnimator.glideSpread`, 1.4 rad).
  - `TouchControls` puts a row left of sneak: a button for each of the game's actions with
    an icon (held while the finger is on it), then fly in creative (lit while flying) and
    glide while the bag holds a glider.
  - The library re-exports `PhysicalKeyboardKey` and `GamepadButton`, so a game declares
    its actions with one import.
  - The example declares two actions (F1 the controls, a screen's action; T the time, read by
    a system), a glider it starts with and crafts from wool, and opens on the title, whose
    Creative worlds fly.
- **Sound catches up, footsteps (VA17b).** A block tagged `step:<kind>` sounds `step_<kind>`
  when walked on; untagged, `step_<family>` as before (its `sound:` tag, else the guess).
  `VoxelGame.stepSound` (new) is that choice. A `step:` kind must be a sound the game has —
  stock (sound_recipes adds `step_sand` and `step_snow`), one of `SoundSpec.recipes` or of
  `SoundSpec.assets` (`SoundSpec.has`, new) — or `VoxelGameSpec.checkSteps` (new, run when
  the game is made) throws, as it does for a block tagged twice (`SoundSpec.stepKindOf`,
  new). Recorded takes declared as `SoundSpec.assets` under a stock name (`step_snow`)
  play instead of the synthesised one, with no code. The example tags its sand, soul sand
  and gravel `step:sand` and its snow `step:snow`.
- **Sound catches up, music (VA17a). Breaking:** `SoundSpec.music` is a `MusicSpec?`
  (new; null, the default, is no music) instead of a map of moods to asset paths. A
  `MusicSpec` names its `tracks`, each a `MusicTrack` (new): a `MusicScore` synthesised at
  first play, with no files, an `asset` that plays instead when the game bundles it, or both,
  and an optional `title`. The places that play a track name it, the first that applies
  winning: `dimensions` (by dimension id), `cave` (underground: well below the ground and
  out of the sky's light, as before), `biomes` (by name, day and night alike), `day`, and
  `night`, whose null keeps the day's track playing. `MusicSpec.trackAt` is that choice;
  `VoxelGameSpec.checkMusic` (new, run when the game is made) throws for a place naming no
  track, a biome no dimension's world has, or a dimension not declared. `VoxelGame` picks
  the track once a second in its step (`VoxelGame.musicTrack`, new: null with no music, the
  sound off, or before the player stands) and tells a track's title on a change
  (`♪ <title>`); `VoxelGameWidget` plays it through a `MusicDirector` keyed by track, so two
  places on one track (day and night, two biomes) no longer fade it into itself. The
  settings offer the music's volume when `music` is not null. `MusicScore` and `StockMusic`
  are exported. The example declares six stock tracks over its biomes, its caves and its
  underworld.
- **Net catches up, last part: floats, seats and shots (VA16g).** Every player sees what
  the others do with a rod, a seat and a shot. A player's pose (a client's `pose`, a row of
  the host's `state`) carries its float while a line is out (`f`) and the way its seat
  points while it rides (`s`). `RemotePlayer.setPose` takes both (`float`, `seat`, new
  getters too): a `RemotePlayer` draws the float as a `Bobber.replica` (new: it goes where
  the pose says, never bites, and goes with its owner) whose line hangs from its hand
  (`RemotePlayer.drawnHand`), and sits while its peer rides, facing the seat. `Bobber.owner`
  is an `Angler` (new: `drawnHand`, `removed`), which `PlayerEntity` and `RemotePlayer`
  are. The seated pose is new for the local player as well: `RigInstance.animate` and
  `RigAnimator.pose` take `seated`, a humanoid's legs out in front
  (`RigAnimator.seatedLegs`), drawn `RigInstance.seatDrop` (new; `RigModel.seatDrop`) below
  its feet so its thighs rest at the seat's height; the other body plans only stand still.
  Shots cross: `VoxelGame.shoot` hands each shot to the session (`GameSession.fired`, new).
  The host shows its own to every client (`shot`: its dimension, its spec, where from, how
  fast, and its shooter, a player's peer or a creature's number), drawn as a
  `Projectile.replica` (new: it stops where it hits and hurts nobody). A client shoots for
  its own player only (anything else throws) and sends it (`shoot`); where the host is, its
  own copy is a replica and the host lands the shot, its puppet the shooter (critical as a
  player's: a shot by a `RemotePlayer` rolls `PlayerSpec.critChance` too), and every other
  client sees it wherever. `ProjectileSpec.toJson` / `ProjectileSpec.fromJson` (new) carry a
  shot whole; one with no size or life, a light, trail or burn below none, or an effect on
  hit the spec does not declare throws, as does a float where the spec does not fish.

- **Net catches up, sixth part: vehicles (VA16f).** A client puts down, gets on, drives,
  gets off and breaks the host's vehicles. The host numbers every vehicle of its dimension
  (`Vehicle.netId`, new) and sends it (`vehicles`: its save row and its rider's peer, with
  the hello, on a client's arrival in the host's dimension, and 20 times a second for those
  that moved or changed rider); a client draws `Vehicle.replica`s (new) and drops them on
  `vehicles_gone`. `VoxelGame.placeVehicle` on a client where the host is hands the vehicle
  to the host (`GameSession.handOffVehicle`, new) and returns null (it returns `Vehicle?`
  now, as `dropStack` does); a vehicle put down from another dimension goes back to the bag.
  A use on a replica asks for the seat (`GameSession.boardVehicle`, new; `vehicle_board`):
  the host gives it when nobody has it, the client hears where the vehicle stands
  (`vehicle_boarded`) and gets on from there. As VAD9 says, the rider drives: the client's
  copy is the live one, its `pose` carries the vehicle's row, and the host's copy follows it
  (`Vehicle.followRow`, new, which a replica also follows the host's by). Getting off is a
  `vehicle_leave` with where it was left, and the host's copy goes on from there, a cart at
  the speed it had (`Vehicle.takeOver`, new); a peer that leaves gets off where it last
  drove. A swing at a replica nobody rides asks the host to break it
  (`GameSession.breakVehicle`, new). `Vehicle.takes`, `placeVehicle` and the swing lose their
  `authority` gates; a replica is never broken, parked or saved by the client
  (`breakApart` throws for one), and `VoxelGame.vehicleFrom` (new) makes a vehicle from its
  row, as a load, a trip back and a replica do. A kind's move without a rider is
  `Vehicle.alone` (was `tick`). A pose driving a vehicle the peer did not get on, or a row
  of another vehicle's item, throws.

- **Net catches up, fifth part: creatures (VA16e).** A client tames and rides. A use with
  what tames the host's creature (`PlayerEntity.usableOn` now takes a replica) spends the
  item on the client and asks the host (`tame`, through `GameSession.tameMob`, new); the host
  rolls `tameChance`, the client's puppet owns what took, and the client hears which
  (`tamed`, said by `PlayerEntity.tamingTried`, new). An offer to a creature tamed or gone
  meanwhile is handed back. A mob's row in `state` names its owner's peer and its rider's
  (`GameSession.hostPeer`, new, is the host's player), and a replica takes its owner from it
  (`Mob.applyNetState`'s `owner`). A client rides its own pet at once (`Mob.takes` no longer
  refuses a replica: only its owner rides it, so nobody else could), and drives it as VAD9
  says: its copy is the live one, its `pose` carries the mount's, and the host's copy follows
  it (`Mob.followRider`, new) with its brain at rest, even where the host has no world; a
  pose without it, or the peer leaving, hands it back to the host. A `RemotePlayer` whose peer
  left is dead to every creature: hunters let it go and its pets wait. A pose that rides
  another's creature, or an offer of what does not tame it, throws.

- **Net catches up, fourth part: the sky (VA16d).** A client's weather is the host's. The
  host sends its sky (`weather`: the spell, the last rain or storm, the intensity it eases
  toward and the one it stands at) with the hello and each time it turns; the client
  `Weather.follow`s it (new, with `Weather.wet` and `target`), starting where the host's
  stands and easing as the host's does, so a joiner under a storm has it at once and a sky
  the host sets at once is at once everywhere. What falls is still the client's own biome's,
  and each side strikes its bolts on its own clock. A client whose player turned the weather
  off stays clear and eases into the host's sky when it is turned on. A sky no host sends
  (snow as a spell, an intensity out of range) throws.

- **Net catches up, third part: stores (VA16c).** A client opens a store where the host is
  (`VoxelGame.storesHere`, new; `openScreen(StorageScreen)` no longer throws on a client
  there): `store_open` / `store_close` as its screen opens and shuts. The host keeps the
  store: it sends it then and at every change to whoever has it open (`store`), its own
  screen seeing the peers' edits too, and shuts a store gone, broken, placed anew or left
  behind by the host's trip (`store_shut`), which closes the client's screen. A store where the
  host has no world (another dimension, a chunk it has not loaded) shuts at once. On the
  client, `VoxelGame.openStorage` is the host's store as last sent with the client's unsettled
  edits over it (`GameSession.storeAt` and `hostHere`, new). Each slot the client changes is
  a `store_set` (its number, the slot, what it held before and after), checked by the host as
  VAD8 says: it stands only on the slot the client saw (compare-and-set), and what it puts in
  must be paid, out of what the client took from this store since it opened it, then out of
  what it last declared it holds (`RemotePlayer.spend`, new). The host answers with the store
  and a `store_ack`; a refusal undoes the client's share, the stack in hand too
  (`ClientSession.pendingStoreEdits` / `storeRefusals`). So two players taking one stack end
  with one stack between them. The stack in hand left the bag's screen for the player
  (`PlayerEntity.carried`, `clickSlot`, `throwCarried`, `stowCarried`, new), and a client
  declares it beside its bag (`bag`'s `c`, `RemotePlayer.carried`), checked every 0.2 s and
  sent when either changed.

- **Net catches up, second part: drops and the bag (VA16b).** The host owns every item on the
  ground. It numbers each drop its game makes and announces it at the end of the step
  (`drops`: number, stack, position, with the host's dimension), sends 10 times a second the
  drops that moved more than 5 cm (`drop_poses`) and the gone ones (`drops_gone`); a client
  draws them as replicas (`ItemPickup.replica`, `netId` and `setNetPose`, new), lerped to the
  host's poses, and only in the host's dimension. The hello carries the drops there are
  (`joinHost`'s `drops`, which `ClientSession` now requires), and a peer coming back to the
  host's dimension is sent them again. `VoxelGame.dropStack` on a client where the host is
  becomes a request (`drop`) the host makes, and returns null (`dropStack` and `dropItem`
  now return `ItemPickup?`): one path for a break's loot (rolled by the client, which knows
  the tool), a throw, a bag's overflow and a catch's rest. Where the host is not, it steps no
  world, so the client keeps its drop itself; a request that crosses a trip goes back to the
  bag. The host decides every pickup: the nearest living player in its dimension whose bag
  takes some of the stack, its own or a peer's puppet. A peer's share goes to it as `give`;
  what its bag no longer takes comes back as `give_rest` and lands at the puppet's feet, out
  of reach for 2 s (`ItemPickup.wait`, new). A client declares its bag when it changes, at most
  5 times a second (`bag`); the host keeps it as `RemotePlayer.bag` (with `roomFor` and
  `give`, new), counts what it hands over until the next declaration, and pulls nothing toward
  a bag that takes none of it, or one not declared yet. The game's own player is no longer
  pulled toward with a full bag either. A drop where its side has no world (a far client's, on
  the host) waits where it is: an unloaded cell reads as air, and it fell to the world's floor.
  A malformed stack, bag or dimension throws.

- **Net catches up, first part: blocks (VA16a).** A client's block edit shows at once and goes
  to the host as a request (`requests`: its number, the cell, the id it replaced and the id it
  wrote, a message per dimension and step). The host keeps it only where its own block is the
  one replaced (compare-and-set: of two players on one cell, the second is refused) and answers
  each with an ack carrying the id that stands (`acks`); a client whose edit lost rolls back to
  it, and the roll back is not sent again. Until its ack an edit owns its cell, so the host's
  echo of that cell, older than the ack, waits. Where the host has not loaded the world, or in
  a dimension it is not in, the edit is taken unchecked, passed on to the others and acked as
  asked. `ClientSession.pendingEdits` and `rollbacks` (new). A message no peer of the same spec
  sends (a block id out of the registry, an undeclared dimension, an ack for no edit) throws.
  A client's lever: `VoxelGame.useSignal` (new) flips a lever or presses a button — through
  the circuits on the authority, as a block edit of its own on a client, which the host's
  circuits answer (the lamp lights on the host and every client); before, a client's use on a
  lever fell through to building against it. `VoxelGame.signals` stays null on a client.

- **Vehicles and fishing, third part: fishing (VA15c).** `VoxelGameSpec.fishing`, a
  `FishingSpec` (`rod`, `catches` — a `LootTable`, a `LootTable.oneOf` for one catch a bite —,
  `liquids` `{'water'}`, `reach` 8, a wait of `minWait`–`maxWait` 3–8 s, a `bite` of 1.5 s,
  `xp` 2), checked at start (`checkFishing`: the rod an item that places no block, every
  catch an item, one-of slices summing to 1 at most, every liquid a block's, and experience
  only with `PlayerSpec.xp`). A use with the rod in hand, on a press only, casts a `Bobber`
  at the surface of the first of those liquids along the aim ("Cast at water" otherwise): it
  flies there in an arc (2.2 of its flight a second, 1.4 m high), floats bobbing, and after
  the wait something bites ("Something bites!"): it dips for the bite's seconds, and a use
  then lands one roll of the catches in the bag (`pickUp`; what does not fit falls at the
  player's feet; "Nothing on the line" for an empty roll) and the experience. A use while
  nothing bites reels in empty ("Reeled in"); the line is reeled in when the rod leaves the
  hand, when the player is twice the reach from it, and when the player dies, and forgotten
  when a trip takes it away. A line runs from the hand to the float every frame
  (`PlayerEntity.drawnHand`). `PlayerEntity.bobber`. The example fishes: a `fishing_rod`, a
  `raw_fish` (food), and catches one-of 70 % a fish, 10 % two, 15 % a bowl, 5 % a lighter.

- **Vehicles, second part: rails and a minecart (VA15b).** `Rails` (`VoxelGame.rails`): a
  block of a rail shape (`BlockShape.railNs` … `railSlopeW`) is a rail of the kind it drops,
  and a powered rail on (a value of `SignalSpec.poweredRails`) speeds a cart while one off
  brakes it, over the engine's `RailGraph`. Where the game is the authority a rail laid
  turns to meet the rails around it — a straight, a curve, a slope up onto a block — and
  turns them to meet it; one taken away lets them turn back. Checked at start: two rails of
  one kind, shape and state, a kind that lacks a shape it turns into (both straights, and in
  each state what it has in another), or a powered rail of no rail shape throw.
  **Breaking:** a game whose rail kind had one straight alone now throws at start; give it
  the other (`powered_rail_ns`) with the same drop. A `CartSpec` (the app's numbers: 8 m/s
  top, 4 down a slope, 0.4 friction, 6 on a powered rail on, 12 braking on one off, 2 a
  rider's push; a cart of iron on four wheels from its `model`) is a `Minecart`: it rides
  the rails from the end of each it came in by to the one it leaves by (`cell`, `heading`,
  `along`, `speed`), rolls down slopes and back off climbs, onto the next rail that joins
  (a slope a cell down too), and stops at the line's end turned to roll back; with no rail
  under it, it stays where it is, and a rail turned under it keeps it heading the nearest
  way. Its rider pushes it by the move along the ground along its heading (and back
  against it); one with no rider rolls all the same. The player puts one on the aimed rail
  with its item in hand, heading for the end nearest the look ("A minecart goes on rails"
  otherwise). The save keeps where it is on the rails and how fast it goes
  (`Vehicle.restoreRow`, which `restoreVehicles` calls on the row). The example lays its
  rail in every shape (`rail_ns`, the curves, the slopes, all dropping `rail`; appended, so
  saves keep their ids), crafts rails and a minecart, and declares `CartSpec(item:
  'minecart')`.

- **Vehicles, first part: a seat and a boat (VA15a).** `Rideable`: anything with a seat (a
  rider, a name, where it stands and points, `seat()`, `takes(rider)`, `gone`, and
  `carry(dt, RideInput)`, the move along the ground plus its forward and turn axes, sprint
  and jump). `Mob` is one. **Breaking:** `PlayerEntity.riding` is a `Rideable?`,
  `PlayerEntity.ride` takes any `Rideable` that `takes` the player (it throws otherwise, and
  while the player rides already), and `Mob.carry(dt, wish, sprint:, jump:)` is
  `carry(dt, RideInput)`. A rider faces the way its seat points; one riding something no
  longer uses a mount of theirs (`usableOn`), which threw before. `VoxelGameSpec.vehicles`:
  `VehicleSpec`s, one an item (`checkVehicles`, run at start: the item exists, places no
  block, and is no other vehicle's). A `BoatSpec` (the app's numbers by default: 6.5 m/s
  rowed on liquid, 1.5 on land, 1.7 rad/s turn, a hull of planks drawn from its `model`
  boxes) floats on any liquid and settles at its surface, is rowed by the move's forward
  axis and steered by its right axis, coasts to rest without a rider, waits while its chunk
  is not loaded, and rolls and bobs to the eye. The player puts one on the first liquid
  along the aim with its item in hand (one used up, not in creative; "A boat goes on water"
  otherwise), rides it by a use on it (`aimedVehicle`, the nearest of block, creature and
  vehicle; a finger's tap boards it), gets off with sneak, and breaks one nobody rides with
  a swing, back into its item (none in creative; `Vehicle.breakApart`). `VoxelGame.vehicles`,
  `vehicleFor`, `placeVehicle`. A client neither puts one down, boards nor breaks one: the
  host owns them (VA16). `travel` gets the rider off first, and a vehicle stays where it was
  left: the dimension's vehicles are parked (`parkedVehicles`) and put back on the way back
  (`restoreVehicles`). `game.json` is version 7: `vehicles`, every dimension's (`Vehicle.row`:
  item, position, facing; `VoxelGame.vehicleRows`), no rider; a version 6 save loads with
  none, and a network hello brings none. The example gains a boat (five planks).

- **Combat feel (VA14).** A blow from outside is felt: its victim's pose holds for
  `Mob.hitStop` (0.06 s, `frozen`), it shows white for `Mob.hitFlash` (0.1 s, `flashing`)
  and shakes, and a shove carries it as before (`CharacterMotor.shove`'s stagger); a burn's
  or an effect's tick only shakes it. The same on a client's replicas, and on the player's
  own model in third person. The player's camera shakes by the damage taken
  (`PlayerEntity.shake`: the damage over 10, at most 0.3 m, over 0.15 s) and no longer by an
  effect's tick or hunger. A creature that dies topples over in `Mob.toppleSeconds` (0.4 s)
  and fades out in `fadeSeconds` (0.3 s), gone at 0.7 s (it lay 1.2 s before, never fading;
  `Mob.opacityAfterDeath`). `PlayerSpec.critChance` (0, none, by default) and
  `critMultiplier` (1.5): a swing or a shot of the player's may be critical
  (`PlayerEntity.critical`, the damage multiplied and rounded), `Damage.crit` carries it to
  the victim and over the network, and its number is yellow, ending in `!`
  (`DamageNumbers.add(crit:)`, `DamageNumber.crit`, `DamageNumbers.label(crit:)`).
  `Mob.ignite`: a creature set alight burns for that long (`burning` at once, 0.5 a half
  second, the daylight rule's numbers); liquid puts it out. Burning, a creature is drawn
  orange and sheds an ember a burn. `Mob.tint` is what a rig's colours are multiplied by: a
  burn's orange, a ghost's see-through pale blue (`MobSpec.ghost` is drawn see-through now:
  `KL-015` closed), and a death's fade. `RigInstance.paint` draws a rig in one of
  voxel_scene's shared materials (`VoxelModelMesh.flash`, `tinted`), so creatures in one
  look still batch. `VoxelGame.debris` (voxel_scene's `DebrisParticles`): a block mined
  sheds two chips a dig and a dozen when it breaks by the player's hand (`VoxelGame.chip`,
  shaded by the light on the block's faces); a blast's blocks shed none.
  `ProjectileSpec.light` (the reach of a light in its colour), `trail` (a see-through
  streak behind it), `burns` (seconds a creature it hits burns) and `onHit` (a `HitEffect`
  left on the player it hurts; `checkMobs` refuses one the spec does not declare);
  `ProjectileSpec.bolt` now lights its way and trails, and `ProjectileSpec.fireball` is new.
  The example's player has a crit chance of 0.1, and a wisp (a see-through ghost) comes at
  night to throw fire, which burns the player through the example's `burning` effect.

- **Creatures grow, last part: kept in the save (VA13c).** `MobSpec.persistent`: the
  spawner never takes it away (nor counts it), however far the player goes. `MobSpec.ghost`:
  it passes through blocks (`noclip`); a ghost must fly (`Gait.fly`), or `checkMobs` throws.
  It draws as solid as any creature for now (`KL-015`). `game.json` is version 6: `mobs`,
  by dimension, keeps every tamed and persistent creature of the dimension the player is in
  (id, position, facing, health, level, tamed); a load spawns them again, a tamed one owned
  by the local player. A wild creature is not kept, a version 5 save loads with none, and a
  network hello (no player) brings none: the host's creatures come by the session.
  `Mob.facing` is a field a game can set. The example's tamed wolf and horse come back
  with the world.

- **Creatures grow, second part: tamed, companions and mounts (VA13b).** `MobSpec.tameWith`
  (items) and `tameChance`: a use with one in hand on the creature spends it and, at that
  chance, tames it (`Mob.tame`, `owner`, `tamed`); it then thinks with
  `MobSpec.tamedBrain`, never burns by day and is never despawned. Three new behaviours:
  `PetFight` (the nearest wild creature hunting the owner or hurt by them in the last ten
  seconds becomes its `target`, for a `MeleeAttack` beside it), `Heel` (follows past 4 m,
  stops within 2, is carried beside the owner past 30, `Mob.teleport`) and `MountWait`
  (trots after the owner 4 to 20 m away). `MobSpec.mount` (`MountSpec`: seat, pace, sprint,
  jump): the owner rides it by a use (`PlayerEntity.ride`, `riding`, `Mob.rider`,
  `Mob.carry`, `Mob.seat`); the move, sprint and jump go to the mount, and a press of sneak
  gets off (`dismount`), as does the mount's death or the rider's. `PlayerEntity.usableOn`:
  a finger's tap on a creature the hand can use uses it rather than swinging. A client
  neither tames nor rides the host's creatures yet. `checkMobs` also rejects an unknown
  taming item, a chance outside (0, 1] and a tameable creature with no `tamedBrain`. The
  example gains a wolf (mutton tames it into a companion) and a horse (an apple, then ride).

- **Creatures grow, first part (VA13a).** **Breaking:** `Drop` is gone; a creature's
  `MobSpec.loot` is a voxel_engine `LootTable`, rolled once when it dies (`drops:
  [Drop('wool', 1, 2)]` becomes `loot: LootTable([LootEntry('wool', 1, 2, 1.0)])`).
  `MobSpec.xp`: the experience the player gains when their blow kills it (a spec with a
  creature worth some and no `PlayerSpec.xp` throws at start). `MobSpec.levels`
  (`MobLevels`): a natural spawn comes at the player's level plus one, give or take
  `spread`, plus `caveBonus` in a cave, and each level adds a share of the health, of every
  strike's damage (melee, a shot's, a blast's) and of the experience; `Mob.level`,
  `growTo`, `maxHp`, `damageScale`, `xpWorth`. `MobSpec.burnsInDaylight`: under the open
  noon sky (head at sky light 15, daylight 0.9 or more), out of liquid, half a point twice a
  second (`Mob.burning`). `MobSpec.splitsInto` (`MobSplit`): it dies into `count` of another
  mob at its level. `MobSpec.onHit` (`HitEffect`): its strike leaves a status effect on the
  player (`Mob.strike`, which every strike of a behaviour goes through). `SpawnRule.place`
  (`SpawnPlace`: surface, cave, anywhere; it replaces `onSurfaceOnly`, which nothing read),
  `SpawnRule.cave()`, `SpawnRule.biomeWeights` (`weightIn`): while the player is
  `MobSpawner.caveDepth` under the ground of their column, `caveShare` of the tries are a
  pocket of air near their height; in a dimension that is all cavern every try is. `dark()`
  now spawns in caves too. `VoxelGame.shoot` and `Projectile` take a `power`.
  `VoxelGameSpec.checkMobs` (run at start): two mobs of one id, unknown loot, an undeclared
  split or effect throw. The default HUD reads a creature's `maxHp`. The example's
  creatures carry their loot and experience as rows (its `onMobKilled` is gone), its zombie
  grows and burns, and it gains a poisonous cave spider and a slime that splits, thickest
  in the swamp.

- **Pistons and powered rails (VA12).** `SignalSpec.pistons` (new, retracted to extended):
  powered, a piston pushes the block in front of it one cell on when that block breaks
  (hardness ≥ 0), holds no store, is one cell high and the cell past it takes a block (air,
  a plant, a liquid); else it stays in. Unpowered, the head goes back and pulls nothing. It
  pushes the way its retracted block faces in a `Facing.compass` (north -Z, east +X), so a
  placed piston pushes away from the player; a piston that is no compass variant throws an
  `ArgumentError` when the game starts. `SignalSpec.poweredRails` (new, unpowered to
  powered) and `railReach` (8): rails joined side by side are a run, lit within `railReach`
  rails of a powered one. Both over voxel_engine's `SignalReactions.piston` / `poweredRun`.
  The example declares circuits for the first time: a wire, a lever, a lamp, four pistons and
  powered rails along either axis, each with a recipe; its blocks are appended, so a save
  made before keeps its ids.

- **A richer world (VA11).** The kit re-exports voxel_engine's new world rows — `Stratum`,
  `Cover`, `Pools`, `Structure`, `CustomStructure` and the stock structures `Dungeon`,
  `Tower`, `Well`, `Camp`, `Ruins`, `Mine`, `Village`, `VillageFarm` — and with them the new
  `StructureSpec(name, structure, ...)` (breaking: a build function is a
  `CustomStructure`). The example's world wears them: peaks with snow over 101 and gravel,
  a tundra with ice, a desert of cacti, a swamp of pools, mud, reeds and willows, a jungle of
  giants and melons, a forest of oaks and big oaks by weight, dark stone under y 22, a sea
  floor of sand and gravel, and all seven structures. Its world (and the benchmark's, which
  is the example's) is not the one it was: a save made before keeps its edits over new
  ground.

- **Dimensions and portals (VA10).** `VoxelGameSpec.dimensions` (new, `{id: WorldGenSpec}`,
  empty by default): the worlds beside `world`, whose id is `VoxelGameSpec.mainDimension`
  (`'world'`; a dimension of that name throws); `dimensionIds` and `dimensionWorlds` number
  them, `world` first. Every dimension is generated from the game's seed; one streams at a
  time.
  - `GameWorld(blocks, dimensions, seed)` and `GameWorld.headless` take every dimension's
    spec (was one `WorldGenSpec`): `generators` (voxel_engine's `DimensionGenerator`),
    `dimension`, `generator` the streaming one's. `switchDimension(d)` drops every chunk,
    mesh and light of the one streaming, its edits kept, and the liquids' queue;
    `storeEditIn(d, cell, id)` keeps an edit for a dimension not streaming, which lands when
    it streams that chunk; `editCountIn(d)`; `arrivalAt(x, z)`: the feet's cell nearest the
    column's surface with two clear cells over firm ground, in the column or the nearest
    four out, a pocket of the dimension's stone and air carved above its sea where there is
    none.
  - `VoxelGame.travel(dimension, at:, through:)` takes the player there: the creatures and
    the items of the dimension left are dropped, a store's screen shuts, the player waits
    off the ground (`ready` false; `PlayerEntity.hold` / `placeAt`, new) while the world
    keeps stepping, then stands at `at` or at its column's arrival. `VoxelGame.dimension`
    (the id), `travelState` (a `Travel`, new, sealed: `Staying`, `Charging` with its
    `progress`, `Arriving`, `Lingering` — in a portal after a trip, which charges only once
    the player has stepped out). A respawn from another dimension travels to the spawn in
    the main world.
  - `VoxelGameSpec.portals` (new) of `PortalSpec` (new): a `frame` block around a hollow
    `width` × `height` (2 × 3) in either vertical plane, the `lighter` item that fills a
    closed one with `portal` blocks (used on it: `PlayerEntity`'s use, so every input
    device), `from` (the main world) and `to`. Standing in one for `seconds` (2) goes to its
    other end, to the same column; a return portal is built in front of the arrival unless
    a lit one lies within `search` blocks. `VoxelGame.portals` (`Portals`, new: `at`,
    `lights`, `lightWith`, `light`, `build`, `nearest`). `VoxelGameSpec.checkDimensions`
    (new; `VoxelGame` runs it) throws for a portal of an undeclared dimension, from and to
    one, of unknown or solid portal blocks, two of one block, or an unknown lighter.
  - Each dimension keeps its own crops, stores and circuits: `BlockRules.growing` and
    `stores` are the streaming dimension's, `growingIn(d)` / `storesIn(d)` any one's,
    `restoreGrowing` / `restoreStores` take a `dimension:`; `VoxelGame.signals` is now the
    streaming dimension's network (a getter; was a field).
  - The save: `game.json` version 5 adds the dimensions in the order `edits.bin` holds them,
    the player's dimension, and the crops and stores by dimension; `edits.bin` is version 2,
    every dimension (`WorldSaves.codecFor(n)`, new, replaces `WorldSaves.codec`). A version
    4 save and its version 1 `edits.bin` still load, all of the main world.
    `SavedWorld.dimensions` (new) names the dimensions its `edits` number, and
    `editsFor(ids)` renumbers them for a game (a dimension it does not declare throws).
  - The network: an `edits` message carries its dimension (`d`), and a host stores and
    passes on a client's edit of a dimension it is not in; the hello names the dimensions;
    a player's pose carries its dimension (`RemotePlayer.dimension`, new), so another
    dimension's players are not drawn nor hunted (`VoxelGame.playersHere`, new; what
    `allTargets` and `targetsOf` read); the host's mobs are its dimension's, and a client
    elsewhere sees none. A host steps only its own dimension: a client in another has no
    liquids, block rules or mobs there until VA16.
  - `Weather(spec, worlds, seed:)` takes every dimension's spec (was one), so a biome of any
    of them may have its own odds.
- The example has an underworld: a cavern of hellstone over a lava sea, soul sand where it is
  wet, glowstone hanging, reached through an obsidian portal lit with flint and steel (both
  crafted).

- **Weather (VA9).** `SkySpec.weather` (a `WeatherSpec`, new; null, the default, keeps a
  sky that is always clear): a sky rolled every `minSpell`..`maxSpell` seconds from
  `WeatherOdds` (new: clear, rain, storm weights; `WeatherOdds.alwaysClear`) or a biome's own
  (`WeatherSpec.biomes`, by `Biome.name`; a name the world lacks throws), eased in over
  `fadeSeconds`. `VoxelGame.weather` (a `Weather`, new): the sky's `spell`, the `kind` where
  the player stands (`WeatherKind`, new: clear, rain, storm, snow — a rain or storm over a
  biome whose `precipitation` is snow snows, over one whose is none nothing falls but the
  sky still greys), `intensity`, `overcast`, `flash`, `rainShare` / `snowShare`, and `set`
  (a spell from code, eased or `now`). The frame greys and dims the sky, sun, ambient and
  sky light and pulls the fog in by `overcast` (voxel_scene's `DayNightSky`), and the rain
  and snow fall around the player (`VoxelGame.weatherParticles`, voxel_scene's
  `WeatherParticles`); a storm strikes every `minBolt`..`maxBolt` seconds, a white flash and
  `WeatherSpec.thunder`. Only an `authority` rolls: a client's sky stays clear until the host
  sends its own (VA16). Not saved: a world loads clear.
- `GameSettings.weather` (new, on by default): off clears the sky at once and holds it; the
  `SettingsPanel` offers it when the spec declares weather. `settings.json` is version 2; a
  version 1 file still loads, the weather on.
- The example's sky has weather; its benchmark pins the example's day with none, so a storm
  is never measured as a regression.

- **Worlds and the title (VA8).** A game opts in with `runVoxelGame(spec, menu:
  TitleSpec(...))` and opens on its title; without `menu` it still drops straight into its
  world.
  - `WorldSaves` keeps a `world.json` per slot (version 1), read as a `WorldInfo` (new): the
    name, the seed, the `WorldMode` (new: survival or creative, or none for a world that
    plays as the spec declares), when it was made, when last played and for how long (game
    time). `create(name, seed:, mode:)` makes a world in a slot of its own (its name in lower
    case, a number after it when taken) and writes only that file; `rename` keeps the slot;
    `info`, `worlds()` (the last played first) and `contains` read it; `save` writes it beside
    `game.json`. `WorldSaves.seedOf` turns typed text into a seed: a number is itself, other
    text its FNV-1a hash, nothing a random one. `WorldSaves` takes a `clock:`.
  - A slot saved before `world.json` still lists and loads: its name is its slot, its seed
    and play time come from `game.json`, when it was made is unknown; its next save writes
    the file. `list()` now lists a world made and not yet played too; `exists` still means
    "has a saved game".
  - `WorldInfo.applyTo(spec)` plays a world with its seed and mode; `VoxelGameWidget` does it
    for a `saveSlot` that is a world, so a world made and not yet played grows from its seed.
  - `PlayerSpec.copyWith` (new).
  - `TitleSpec` (new): name, tagline, whether new worlds pick a mode, whether to offer
    Multiplayer and on which port, the credits, a background. `TitleScreen` (new): Play
    (`WorldList`, new), Multiplayer (host a world of the list on the port, with this
    machine's addresses shown; join `host` or `host:port`), Settings (`SettingsPanel` on the
    `SettingsStore` directly), Credits (`CreditsRoll`, new), Quit on a desktop; Escape
    leaves a panel. `VoxelGameHome` (new) puts the title and the game one after the other
    (`TitleChoice`: `PlayWorld` or `JoinHost`); the game menu's Quit saves and returns to the
    title.
  - `VoxelGameWidget.onNetError` (new): a join that reaches no host, or a port already taken,
    is handed to it (the title says why) instead of failing behind the loading screen.
  - `runVoxelGame` throws for `menu` with `saveSlot`, `hostPort` or `join`: the title picks.
- **Settings (VA7).** `GameSettings` (new): what the player sets for themselves — render
  distance, look speed, field of view, volume, music volume, view bobbing, the frame rate —
  each checked against its range (a value out of it throws, read from a file or built in
  code). `GameSettings.of(spec)` takes the spec's `renderDistance`, `PlayerSpec.fov` and
  `SoundSpec.musicVolume` as the defaults.
  - `VoxelGame.settings` / `applySettings` put a change in force at once: the world streams
    to the new distance (`GameWorld.loadRadius` now cuts a nearer window back on the spot and
    streams a further one from the next update), the view turns at `InputMap.lookScale`
    (new: the mouse, a finger's drag, `look` and the right stick alike, never a `turn`),
    `ViewCamera` reads the field of view from the settings instead of `PlayerSpec.fov`,
    `ViewCamera.bob` follows `viewBob`, `playSound` plays under `volume` and not at all at 0.
  - `VoxelGame.start` and `joinGame` take `settings:`; `startHeadless` takes the spec's at its
    `loadRadius`.
  - **Breaking:** `VoxelGame.showFps` is gone; the HUD reads `GameSettings.showFps`.
  - `SettingsScreen` (new `GameScreen`): Settings in the game menu opens it; Done and a press
    of pause go back to the menu. `SettingsMenu` shows it, over `SettingsPanel` (new: the
    rows alone, a value in and a change out, offering the volume only with sound and the
    music's only with music), scrolling on a phone held sideways.
  - `VoxelGameWidget` keeps them in a `SettingsStore` (new; `settings:`, by default
    `defaultSettings()`: `<application support>/settings.json`, beside `worlds`), read
    before the game starts and written half a second after a change comes to rest; the music
    plays at `volume × musicVolume`.
- **The bag grows (VA6).** `InventoryScreen`:
  - the held stack follows the pointer, drawn `InventoryScreen.fingerLift` above a finger,
    instead of sitting in a "Cursor" row; only it and the tooltip rebuild as the pointer
    moves;
  - a long press takes half or leaves one, as a right-click does (rule 13);
  - a tooltip, beside the pointer and kept on the screen, says what the slot under the
    mouse holds or, with none (and always under a finger), what is held: the item's name,
    its tool and tier, damage and bonus, uses left, what eating it does, where it is worn,
    the block it places. It replaces Flutter's `Tooltip` of the name alone;
  - a store's slots sit beside the bag, where the recipes are, named by its block; the bag
    is headed "Inventory", the recipes "Crafting" or their station;
  - a stack let go outside the panel (a click or a tap; a right-click or a long press for
    one) is thrown ahead of the player (`PlayerEntity.throwStack`), wear kept;
  - a held stack the bag has no room for when the screen shuts goes on the ground, wear
    kept; it used to be added by id, losing its wear, and what did not fit was lost;
  - the panel scales down to fit the screen (a phone held sideways), never up.
  `PlayerEntity.pickUpStack` puts through the engine's new `Inventory.put`.
- **A dropped stack keeps its wear.** `VoxelGame.dropStack(stack, at)` (new) puts on the
  ground the stack that left a slot, wear and bonus kept; `dropItem` drops a new one, as
  before. `ItemPickup` holds that `stack` (its constructor takes it; `item` and `count` read
  it) and goes back into the bag through `PlayerEntity.pickUpStack` (new): a worn or bonused
  stack takes an empty slot whole, or stays on the ground. A press of drop, a store's spill
  and an armour piece that does not fit when another is put on all drop the stack itself, so
  a pickaxe on its last uses no longer comes back new. Drop throws one of the **selected**
  slot (it took one from the last slot holding the same item).
  `PlayerEntity.throwStack` (new) throws a stack ahead as drop does.
- **Items have a shape (VA5).** One voxel model per item, `VoxelGame.itemModel(id)` (the
  engine's `ItemModel`, declared by `ItemType.shape` or read off the item's row), drawn
  everywhere the item is:
  - in the first-person hand, which now sways with the walk, lagging the eye, and throws
    the item across the screen on a swing (the hand of `examples/voxel_game_minecraft`);
  - in a humanoid's right fist: `RigInstance.hold(model)` (new; `canHold`, `held`,
    `RigModel.hand`), the player's in third person and every remote player's. A remote
    player's item crosses with its pose (`RemotePlayer.heldItem`; `setPose` takes
    `held:`, and the net's `pose` and `state` rows carry it);
  - as a drop on the ground, at `ItemPickup.size` of its held size, turning about its
    middle. Drops share their item's mesh (`ItemMesh`, voxel_scene) as they shared their
    colour's cube: **`PickupModel` is gone**;
  - as the icon of a hotbar slot and a bag slot: `ItemIcon` (new, exported), the model
    projected once from a top corner (a flat piece face on), recorded as a picture and
    replayed, instead of a square of the item's colour.
  - `VoxelGameSpec.buildItems` throws `ArgumentError` for an item the kit cannot draw: a
    tool of a kind with no stock shape and none declared, or a block's shape on an item
    that places no block.
- **The default HUD reads the world (VA4, the rest).**
  - `VoxelGame.camera()` is the camera of the frame: `frame` builds it once, after the bodies
    are placed, and the scene and the HUD both read it, so a point projected with
    `Camera.worldToScreen` lands where the scene draws it, in the same frame. It used to be
    built anew on each call, by the scene's paint, after the HUD had already built.
  - `DamageNumbers` (new, exported) in `VoxelGame.damageNumbers`, aged by `frame`: a hit on a
    creature adds what it took where the game is the authority, and on a client a replica's
    lost health is the hit (its first state is not one). A replica's `sinceHurt` now counts.
  - The default HUD paints over each creature hurt in the last `DefaultHud.barSeconds` (or
    under the crosshair, within `DefaultHud.barRange`) a health bar, and each hit's number
    rising a metre and fading over a second. It paints nothing, and repaints nothing, while
    there is none.
  - The crosshair turns red on a creature in reach; the mining bar under it is a ring around
    it; a worn tool shows a bar under its slot, green to red.
  - `LiquidSpec.tint` (new, 0.25; lava's default 0.55): the opacity of the wash over the
    screen, in the block's colour, while the camera is in it (`VoxelGame.eyeLiquid`). 0 for
    none. `LiquidSpec.defaultFor(kind)` and `VoxelGame.liquid(kind)` (new) say what a kind
    not in `VoxelGameSpec.liquids` does.
  - `MobSpec.boss` (new): the nearest living one (`VoxelGame.boss`) shows its name and
    health in a bar at the top of the screen.
  - `VoxelGame.showFps` (new, off): the frame rate (`FrameStats.fps`) at the top left.
  - The example has a boss, the brute: rare, at night, one at a time.
- **The default HUD shows survival and tells the player things (VA4).** Each survival piece
  only as the spec declares it:
  - hunger beside the hearts with `PlayerSpec.hunger`, two points an icon;
  - armour over the hearts while `PlayerEntity.armor` is above 0;
  - the experience bar under the hearts, with the level on it past 0, with `PlayerSpec.xp`;
  - the status effects at the top left when `VoxelGameSpec.effects` names some: a row each,
    in its colour, with its power past the first and its time left (`1:15`, `9s`).
  - The hearts follow `PlayerEntity.maxHp`, which a level raises; they used to stop at the
    count of the first frame.
  - `HudSelector.equals` (new): how two values compare, `==` unless given; `listEquals`
    for a list of records.
  - `VoxelGame.notify(text)` (new) tells the player something for three seconds, in a feed
    at the right of the default HUD. Under it, what went into the bag: `PlayerEntity.pickUp`
    adds a line per item (`+3 Dirt`), and a repeat within a second of the last adds to it
    (`+5 Dirt`). Both live in `VoxelGame.notices` (`Notices`, new, exported), which `frame`
    ages; each line is a `NoticeLine` record, fading for its last half second.
  - The example declares `XpSpec()` and gives experience for a kill (`onMobKilled`).
- **Screens as a state machine (VA3).** Breaking: `VoxelGame.openScreen` was a
  `ValueNotifier<String?>` of a station id; it is now a method.
  - `GameScreen` (new, sealed): `BagScreen` (the bag, crafting at its `station`, `''` in the
    hand), `StorageScreen` (the store of a cell beside the bag), `PauseScreen` (the game
    menu), `DeathScreen` and `DeclaredScreen` (a game's own, by id). `VoxelGame.screen`
    holds the one open, or null while playing; `openScreen(screen)` replaces it,
    `closeScreen()` closes it. Each refuses what cannot be: closing nothing, a station no
    recipe names, a store on a client or where nothing stores, an undeclared id, opening the
    death screen (only the player's death does) or anything over it.
  - `VoxelGame.openStorageAt` and `openStorageCell` are gone: `openScreen(StorageScreen(cell))`
    and the screen's `cell`. `openStorage` stays, read from the screen.
  - The step reads the buttons every screen shares: inventory opens and closes the bag and a
    store; pause opens the game menu and closes any screen but the death screen; the
    inventory button does not close the menu or a game's own screen. Pause used to free the
    mouse; it opens the menu, which frees it. A pointer lost mid-play (focus left the window)
    opens the menu too (`VoxelGameWidget`).
  - Death is a screen: the player's death replaces whatever was open with the `DeathScreen`
    (`DeathMenu`, new), which only `VoxelGame.respawn()` leaves, once `canRespawn`. Its
    Respawn button wakes after `PlayerSpec.respawnDelay` (new, 1 s, replacing
    `respawnSeconds`: the timer that stood the player up is gone), and a keyboard or a pad
    stands up with jump. `PlayerEntity.respawn`, `kill` and `deadSeconds` are public. The
    default HUD's "You died" is gone with it.
  - A respawn is no fall: it used to count the drop from where the player died to a spawn
    below it, and hurt them as they stood up (`CharacterMotor.resetFall`, now called).
  - A world saved with the player dead loads with it dead, on the death screen (health 0
    is death; no new save version).
  - `PauseMenu` (new): Resume, a button per `ScreenSpec.menu`, and Quit when
    `VoxelGameWidget.onQuit` (new) is given, called once the world is saved.
    `runVoxelGame` quits the app on a desktop and shows no Quit on a phone.
  - `VoxelGameSpec.screens` (new): a game's own screens by id, each a `ScreenSpec` (new)
    of a `ScreenBuilder` and, for the game menu, a `menu` label.
  - `GameSurface` shows each screen as its widget, keyed by the screen, so one replacing
    another (a death over the bag) gives the bag's cursor back first; it takes `onQuit`.
  - Use opens a station's crafting on a press only, as a store already did.
  - The "click to play" hint hides while a screen is open, and says `E bag, Esc menu`.

- **Blocks that do things (VA2).** Each is a field of a block's row, so a game that
  declares none plays as before.
  - `BlockRules` (new, `VoxelGame.blockRules`) answers every block change of the world: a
    block that `falls` drops to where it lands, through air, plants and liquids, and the
    column above it follows; a block whose `support` is gone breaks and drops, so a torch
    goes with its floor and a wall torch with its wall. Only the authority runs it; a client
    receives the edits it made from the host.
  - A player places nothing where it would not stand (`BlockRules.stands`), and a block put
    against a wall becomes its `onWall` form.
  - `VoxelGame.breakBlock` rolls a block's `loot` when it has one, instead of its `drop`;
    `VoxelGameSpec.buildItems` refuses loot naming an item that does not exist.
  - `VoxelGameSpec.onBlockPlaced` names the block placed, the wall form or the facing
    variant when it was one.
  - A block with a `facing` is placed as the variant the player looks toward (stairs
    climb away from them) or along (a door spans across their way).
  - A `tall` block is placed into the cell above as well, when that cell is free, and its
    halves go together: breaking one takes the other with no second drop. The halves pair
    from the bottom of a run of the block's family (itself, what a use or a
    `SignalSpec.doors` entry turns it into), so two doors stacked stay two doors, and a
    signal swinging a door keeps both halves (`BlockRules.lowerHalf`).
  - A press of use on a block with a `usedInto` turns it (both halves of a tall one) into
    that block, unless the player sneaks; holding use does not flap it. A block that would
    turn solid around a body stays as it is (`BlockRules.use`, `VoxelGame.bodyIn`, which
    the player's placing now shares).
  - A press of use with an empty `ItemType.bucket` scoops the first liquid source along
    the aim that it fills with, leaving air; a full one pours its source against the aimed
    block, where the world's flow spreads it. One of a stack changes: the last in the hand,
    else into the bag. `VoxelGameSpec.buildItems` refuses a bucket of a liquid kind there
    is not, pouring what is not a liquid source, or becoming an unknown item.
  - A press of use with a tool on a block whose `turnsWith` names that tool's kind turns
    the block (a hoe tills grass into farmland) and wears the tool.
  - A block that `grows`, once set in the world, counts the seconds its cell has at least
    `Growth.minLight` (sky or block light), looked at once a second
    (`BlockRules.growPeriod`), and becomes its next stage when they reach
    `Growth.seconds`. What the world generated does not grow. `BlockRules.growing` holds
    each crop's seconds.
  - A block with a `storage` keeps an `Inventory` per cell (`BlockRules.storeAt`,
    `stores`): empty when it is set in the world, filled from `Storage.loot` when the world
    generated it, seeded by `LootTable.seedFor` its cell and the world, the first time it is
    looked into. When it goes, what it holds spills on the ground, a generated one's loot
    included. A press of use opens it (`VoxelGame.openStorageAt`, `openStorage`,
    `openStorageCell`) and `InventoryScreen.storage` (new) shows its slots above the bag in
    place of the recipes; the store is open only while the screen it opened is, and its
    breaking shuts it. A client opens none (the host keeps them; VA16), so its use builds
    against the block. `VoxelGameSpec.buildItems` refuses a store's loot naming an unknown
    item.
  - **`game.json` is version 4**: it keeps the crops growing (`growing`, from version 3)
    and what the stores hold (`stores`). Every older version still loads, a branch on its
    version: before 3 nothing grows, before 4 no store was looked into.
- **Survival on the player (VA1).** Each piece is off until the spec declares it, so a game
  that declares none plays as before.
  - `PlayerSpec.hunger`, a `HungerSpec` (new): the bar empties by `secondsPerPoint`, heals
    `regenAmount` every `regenSeconds` while it holds `regenAbove`, and starves the player by
    `starveDamage` every `starveSeconds` once it is empty. A creative player never gets
    hungry. `PlayerEntity.hunger` is the bar.
  - Food: the item in hand with an `ItemType.food` is eaten on a press of use (holding use
    does not eat the stack), when it would do something (`PlayerEntity.canEat`): fill a bar
    that is not full, heal, or start its effect. It leaves its `Food.leaves` in the bag.
    `PlayerEntity.eatHeld` does it from code.
  - Armour: the item in hand with an `ItemType.armor` is put on by use, and what was worn in
    its slot comes back into the hand (`wearHeld`, `takeOff`, `worn`). `PlayerEntity.armor`,
    the points worn plus what the effects add, turns `PlayerSpec.armorPerPoint` of a blow
    aside a point, never below `PlayerSpec.armorFloor` of it (0.4 and 35 %, the Minecraft
    example's). `PlayerSpec.armorSlots` names the slots; an item worn elsewhere is refused
    when the items are built.
  - Status effects: `VoxelGameSpec.effects` declares them, the player carries them in
    `PlayerEntity.effects` (the engine's `StatusEffects`), a tick's damage and healing land
    on the player, and four stats are read by name: `PlayerEntity.speedStat`, `damageStat`,
    `miningStat` (multipliers) and `armorStat` (points).
  - Experience: `PlayerSpec.xp`, an `XpSpec` (new) curve of `base * (level + 1) ^ exponent`
    points a level, each raising `PlayerEntity.maxHp` by `hpPerLevel`. `PlayerEntity.gainXp`
    adds points, and throws when no curve is declared.
  - `Damage.internal` (new): a hurt from within (an effect's tick, starving) is not turned
    aside by armour and lands through the moment of grace a blow leaves.
  - A respawn stands the player up at `maxHp`, fed, with no effects on them.
  - `VoxelGameSpec.buildItems` throws for a food whose effect is not declared or which leaves
    an unknown item, and for armour worn in a slot the player does not have.
  - A save's `game.json` is version 2 (`WorldSaves.stateVersion`): it keeps hunger, experience
    and level, the effects and what is worn. A version 1 save still loads, its player fed, at
    level 0, wearing nothing.
  - The default HUD draws as many hearts as `maxHp` has. The bars for hunger, experience,
    armour and the effects are VA4's.
  - The example eats and wears: apples to start with, mutton from sheep, a stew (bowl, apple,
    mutton) that heals and regenerates, a wool cap to start with and a wool tunic to craft.

- **A phone plays in landscape, never upright.** `runVoxelGame` locks a phone or tablet to
  the two landscape orientations and hides the status and navigation bars until a swipe
  (`SystemUiMode.immersiveSticky`). The example's runners say the same from the launch
  screen on: `android:screenOrientation="sensorLandscape"` in its `AndroidManifest.xml`,
  landscape only (and `UIRequiresFullScreen`) in its `Info.plist`. A game that mounts
  `VoxelGameWidget` itself sets its own orientation.
- `MeasuredScene`, the scene the game renders, is a voxel_scene `ResizeSafeScene`: the
  frame drawn at a new size (a phone turning to landscape, a window resized, a new render
  scale) draws the sun's static shadows without their cache, so no cached tile begins a
  render pass on a depth texture the resize freed, which crashed the Adreno Vulkan driver
  in the first seconds of a game now and then.
- **A phone gets controls it can see.** `TouchControls` draws a floating stick in the
  lower-left zone (centred where the thumb lands; pushed past `sprintAt` of its reach it
  also holds sprint), jump and sneak at the bottom right, the view and pause at the top
  right, inside the safe area. It shows only while `InputMap.lastDevice` is a finger, the
  game is in `gameplay` and no screen is open. Every control claims its finger, so it is
  never also a look, a dig or a tap on the world. `VoxelGameWidget` mounts it between the
  world and the HUD. It is declared by the new `VoxelGameSpec.touchControls`, a
  `TouchControlsSpec` (`stickRadius`, `stickZoneWidth` / `stickZoneHeight`, `sprintAt`,
  `buttonSize`, `sneakToggles`, `dropHold`), `TouchControlsSpec.standard` by default; null
  for a game that draws its own, which also takes the finger off the default HUD's hotbar.
- The player walks by the on-screen stick: `PlayerEntity` read the left stick and the keys
  but not `InputMap.touchMove`, so a stick drawn by any game moved nothing.
- A finger's tap on a creature hits it. `PlayerEntity` now writes
  `InputMap.touchTapPrimary` every step (true while a creature in reach is under the
  crosshair), which nothing in the kit wrote before, so a tap always pressed the secondary
  button and a phone could only hit by holding, which mines.
- A screen opening lets go of every held input (`InputMap.releaseKeys`), as that method's
  documentation said it did: a switched-on sneak, a finger's jump and the stick no longer
  survive the bag.
- **Breaking: `VoxelGameSpec.copyWith` can ask for null.** Its nullable fields (`signals`,
  `graphics`, `touchControls`, `onBlockBroken`, `onBlockPlaced`, `onMobKilled`, `onTick`)
  are now given as a getter of the new value, so `copyWith(touchControls: () => null)`
  takes the kit's controls away; before, `x ?? this.x` turned a null into "keep it" and the
  call did nothing. Wrap what you passed: `graphics: GraphicsSpec.phone` becomes
  `graphics: () => GraphicsSpec.phone`.
- The bag opens under a `VoxelGameWidget` with no `Scaffold` above it: `InventoryScreen`'s
  panel is its own `Material`, so its recipe tiles no longer fail to build ("No Material
  widget found") in a game that mounts the widget straight under its app.
- `GameSurface`: what `VoxelGameWidget` shows once the game has loaded, the world under
  the touch controls, the HUD and the open screen, inside the one `Listener` and `Focus`
  that feed the input map; it takes the pointer on the first press, keeps a press on an open
  screen from the world, and frees the pointer and every held input when a screen opens.
  `world` is any widget, so the kit's own wiring can be mounted in a widget test, and its
  tests now mount it instead of a copy. `HudBuilder` moved into its file (still exported
  from `package:voxel_game/voxel_game.dart`). A screen opened before the game has loaded
  no longer frees or takes the pointer; the surface arbitrates only while it is shown.
- **Breaking: the HUD is hit-tested.** `VoxelGameWidget` no longer wraps the `HudBuilder`'s
  widget in an `IgnorePointer`, so the default HUD's hotbar can take a finger: a tap on a
  slot picks it, a hold of `TouchControlsSpec.dropHold` on the slot in hand drops one item, and
  while the last device was a finger a `⋯` after the last slot opens the bag. Each slot
  claims the finger that lands on it (`InputMap.claimTouch`), so the world never reads it as
  a tap; a mouse over the hotbar is still the world's. The hint says "Tap to play" while the
  last device was a finger. A HUD of your own that drew plain widgets is unaffected (the
  game's `Listener` sees every pointer either way); one with buttons, `GestureDetector`s or
  `InkWell`s on it now receives their gestures, so wrap it in `IgnorePointer` to keep the
  old behaviour.
- **`InputMap` knows which device spoke last, and which fingers a control took.**
  `InputMap.lastDevice` (the new `InputDevice`: `keyboardMouse`, `gamepad`, `touch`) is
  written by `onKey`, `onPointerDown` and `onPad` from the event each is handed, a pad only
  on a press or a stick past the dead zone; it starts as `touch` on Android and iOS. An
  on-screen control calls `claimTouch(pointer)` from its own `onPointerDown`, and the map
  then reads that finger as no look, no dig and no tap until it lifts. `touchToggle(action)`
  holds an action from one tap to the next (sneak) and `touchHeld(action)` reads it back;
  `touchPress(action)` presses a one-shot for a single step. The pad handler is public as
  `onPad`, so a game can feed a pad source of its own. Nothing on screen changes yet.
- **Breaking: a shot's shape is declared, not read from its kind's name.** `ProjectileSpec`
  takes `thickness` and `length`, the box it is drawn as (only its look; `radius` still
  hits), defaulting to the arrow's `0.06 × 0.06 × 0.6`; `ProjectileSpec.bolt` sets
  `0.5 × 0.5`, the cube it had. `ProjectileModel.of` sized the box by `kind == 'arrow'`,
  so a spear under another name drew a cube and a fireball named `'arrow'` a stick. A
  spec that relied on a kind other than `'arrow'` drawing a cube of its radius now sets
  `thickness` and `length` to `radius * 2`.
- **A loading screen covers the game until it can be shown without a stall.**
  `VoxelGameWidget` runs the game undrawn until the window around the player has filled
  (the new `VoxelGame.filled`: the player stands and `GameWorld.isIdle`), then encodes
  every chunk and body once, offscreen, through flutter_scene's `Scene.warmUp`
  (`includeOffscreen`), so the pipelines Impeller compiles on first use are compiled
  behind the screen. The game keeps stepping while it loads, with its controls off. A
  first run after a build (the Mac, `orbit:6`) drew its first frames in encodes of ~650,
  ~320 and ~570 ms; it now compiles in one ~1.06 s encode before the first frame, which
  encodes in ~1 ms, and fills ~0.4 s sooner; on a Galaxy S24 (a fresh install) the
  encodes of ~330 and ~255 ms become one of ~0.55 s behind the screen, and a warm start
  fills ~0.1 s sooner, the scene no longer drawn while it fills. The screen's stages are the new
  `LoadingStage`; `VoxelGameWidget(loading:)` and `runVoxelGame(loading:)` take a
  `LoadingBuilder` in place of the default `LoadingScreen`. `onReady` still fires as the
  game starts, before the screen goes.
- Drops and shots share their meshes, as the creatures' parts do: `PickupModel.of(r, g, b)`
  builds a drop's cube once a colour, and `ProjectileModel.of(spec)` a shot's box and
  material once a size, colour and glow, so flutter_scene draws a floor of mined blocks
  or a volley of arrows once a pass, instanced, instead of once a drop or a shot. It
  batches only draws sharing both a geometry and a material, and each drop and each shot
  made its own.
- A host passes on a client's block edit that lands where the host has not loaded the
  world. It stored such an edit for when the chunk generates but told no one, so two
  clients far from the host each kept their own blocks until they joined again; now the
  edit leaves with the step's other edits, like one the host could write.

## 0.3.0-dev

- `GameWorld.update` rebuilds the chunk regions the streaming changed within the view's
  frame budget, nearest the focus first (`VoxelChunkView.rebuild`), so a column of chunks
  entering or leaving the window is drawn over a few frames instead of in one long one;
  `GameWorld.isIdle` also waits for the regions still to draw.
- **Breaking: the HUD is built once, not every frame.** `HudBuilder` is called when
  `VoxelGameWidget` builds (the game starts, a screen opens or closes), and the HUD sits
  behind a `RepaintBoundary`, so the scene's repaint every frame no longer repaints it.
  A piece that shows the game's state watches it through the new `HudSelector`, which
  checks a value on every tick of the new `VoxelGame.frames` and rebuilds only when it
  changes; a custom HUD that read the game in its `build` must move those reads into
  selectors. `DefaultHud` is such a tree: while nothing it shows changes, a frame builds
  none of it.
- `RigInstance.place` composes the root's pose into its matrix at once and allocates
  nothing, as `RigPart.apply` now does; every creature is placed every step.
- A networked game sends the block edits of a step together, as one `edits` message at
  the step's end, no longer a `set` message per cell as each was made: an explosion's
  ~120 cells cost the host 1.7 ms with 4 peers and 3.3 with 8 (M2 Pro), a message and a
  write each per peer, against 37 and 50 µs as one. The session now ticks last in
  `VoxelGame.step`, after the game's systems and `onTick`, so every edit of a step leaves
  in it. **The wire changed**: a host and a client of different versions cannot talk.
- The mining crack is one draw: its sticks were a node and a geometry each, up to 60 draws
  at its last stage, and each stage is now one `BoxMesh` (voxel_scene) holding its sticks
  and every earlier stage's, on one node. `FirstPersonView.crackBoxes(stage)` lists them.

## 0.2.0-dev

- **Frames between two steps are drawn between them.** Above 60 fps half the frames ran
  no step, and everything drawn moved in the steps, so the view and every body stood
  still one frame and moved a whole step the next: a 60 Hz world on a 120 Hz display.
  Now `VoxelGame.frame` draws every body `alpha` of the way between its last two steps'
  poses (`NodeBody.drawNode`, the steps keeping the pose before theirs with `beginStep`),
  the camera's eye and the first-person hand follow the drawn player
  (`PlayerEntity.drawnEye`), and the view bob and the third-person pull-out move by
  `VoxelGame.drawnTime`, the game time a frame shows. A frame is drawn a step behind the
  simulation, 16.7 ms. The step is unchanged: 60 Hz, nothing paused.
- **The look is drained once a frame**, by `VoxelGame.frame`, before the steps, and no
  longer by the step: the view turns at the display's rate, and the steps aim with the
  newest yaw. `PlayerEntity.look` applies it (dropped while dead or not yet placed). The
  buttons are still read by the step alone. A game that calls `step` itself, without
  `frame`, turns the player with `look`.
- A rig's facing is its owner's: `RigInstance.place` no longer turns the rig's root, and
  the mob, the player and a remote player turn their node by `rig.yaw` through
  `syncNode`, so a body turns as smoothly as it moves. The limbs are still posed a step
  at a time. The outline around an aimed creature follows its drawn box, once a frame
  (`PlayerEntity.drawOutline`).
- Drops and projectiles set their pose through `syncNode` (a drop's bob and spin, a
  projectile's heading) instead of writing their node, so they are drawn between steps
  too; a respawn or a placement snaps (`syncNode(snap: true)`) instead of gliding there.
- `FrameStats` at 120 Hz, the Mac, `dpr` 2.0: `view judder` 1.0 → 0.0 at `orbit:6` and
  `mobs:6`, 1.0 → 0.05 at `fly:6` (its first four frames, before the flight starts), and
  no other frame shows the view of the frame before.
- `InputMap.turn(yaw, pitch)`: a steady turn from code, radians a second, taken by
  `takeLook` over its `dt` as the right stick's is. A bot, a cutscene or the benchmark
  turns the view the way a held stick does.
- `FrameStats` measures how evenly the view moves, which no frame timing can: a frame
  presented on time may show the view the one before showed. `addView(eye, forward)`,
  which `ViewCamera` calls once a frame, keeps how far the view moved (the angle its
  forward turned, plus its eye's travel over `FrameStats.viewDepth`, 10 m), and
  `addFrame` takes the frame's `seconds`. `FrameReport.viewJudder` is the root mean
  square of each frame's speed against the mean, minus one (0 for a view that moves by
  the time that passed, about 1 for one that moves every other frame) and `stillFrames`
  counts the frames that moved less than a quarter of the mean; the JSON has them under
  `view`. At 120 Hz the kit today reads about 1 and half its frames: the view moves in
  the 60 Hz steps.

## 0.1.2-dev

- The creatures of a species share their meshes: `RigModel.of(rig, halfWidth, height)`
  builds a look at a size once (its parts' voxels as `RigShape`s, their rest poses, the
  fit), and each `RigInstance` hangs only its own posable nodes on it. flutter_scene then
  draws a part once a pass, instanced over every creature that has it, instead of once a
  creature. `Rig` is equal by its values, so two species declared with the same look
  share one model; a humanoid's two legs and two arms, and a quadruped's four legs, share
  one shape. With 40 creatures (`mobs:6`) their meshes go from 260 to 8, and on the M2 Pro
  the shadow pass, which draws every creature again in every cascade each frame, from
  2.4 ms to 0.45 a frame.
- `gamepads: ^0.1.10`, the first version with `NormalizedGamepadState`. The constraint
  allowed `0.1.1-dev2`, which lacks it, so the lowest resolution did not compile and
  pana took 20 pub points.
- Formatted by `dart format` at the 120 columns the code is written at
  (`formatter: page_width: 120` in `analysis_options.yaml`); pana took 10 pub points
  for formatting.
- A step runs at most `Mob.searchesPerStep` (3) A* searches; a mob whose plan is due
  when they are spent plans on a later step (`VoxelGame.searchesLeft`). The random phase
  each mob starts with was lost at its first plan, so hunters that saw the player in one
  step replanned together every 0.6 s, as every hunter does when the player moves 1.5 m:
  up to 18 searches in one step. With 40 creatures (`mobs:6`, M2 Pro) a step's p99 falls
  from 4.5 ms to 1.15, with as many searches a second.
- Fixed: a `Wander`er whose last walk was blocked dropped every later goal at once and
  stood still. `Mob.pathBlocked` belonged to the last plan, which is made after the
  behaviours run, so `Wander` read the verdict on the previous goal. `walkTo` now clears it
  for a goal more than `Mob.replanDistance` (1.5 m, the distance that already triggered a
  replan) from the planned one, until that goal is planned.
- A walking mob replans its path every `Mob.replanEvery` (0.6 s), sooner (never before
  `Mob.replanSoonest`, 0.2 s) only when its goal moved 1.5 m, from a random phase per mob;
  it used to replan every step once its path ran out, which an unreachable goal makes
  happen every step. `Mob.pathsPlanned` counts its searches. With 40 creatures (`mobs:6`,
  M2 Pro) a step costs 0.27 ms instead of 7.8 at the median, and the frame rate goes from
  84 to 93 fps.
- `FrameReport.stepMs`: a fixed step's own cost (each tick's simulation time over the
  steps it ran), in the JSON as `stepMs`. `simMs` grows with the steps a slow frame banks,
  so on a device that is behind it reads `FixedStepLoop`'s cap, not the simulation.
- `GameWorld.isLoaded` and `groundHeight` read the chunk through
  `ChunkStreamer.chunkAtXZ`. With the engine's faster block queries, 40 creatures
  (`mobs:6`, M2 Pro at 120 Hz) run at 91 fps instead of 50, and the simulation's p99 falls
  from 66 ms to 11.

## 0.1.1-dev

- Requires Flutter 3.47.1, the first with a runner setting that turns Flutter GPU on for
  Windows and Linux. The README has the setting for every platform, and why the web is
  not one (worker isolates, TCP sockets and save files need `dart:isolate` and `dart:io`).
  The example's Windows and Linux runners turn it on.
- `FrameStats` (`VoxelGame.stats`): what the frames cost. An `fps` readout, and between
  `startRecording` and `stopRecording` every sample: Flutter's presented frames (interval,
  UI build, raster), the simulation (`VoxelGame.frame`), the scene's encoding and how long
  after it the GPU finished each scene frame (`gpuLatencyMs`: a latency, queue included, not
  the GPU's cost). `FrameReport` summarises them (percentiles, hitches). The scene is a
  `MeasuredScene`, which times its own encoding and the GPU's completion.
- `VoxelGameSpec.copyWith`; `GameWorld.chunksBuilt` and `GameWorld.facesEmitted`.
- `GraphicsSpec` (`VoxelGameSpec.graphics`): `renderScale`, `maxPixelRatio`,
  `antiAliasing` and a `ShadowSpec` (cascades, resolution, distance, the sun's step).
  `GraphicsSpec.desktop` is the look as it was; `GraphicsSpec.phone` draws at most 1.5
  pixels a point, with FXAA and two 1024² cascades over 48 m, and is what a spec without
  `graphics` gets on iOS and Android.
- The camera's far plane ends where the fog is full (`VoxelGame.viewDistance`, plus a
  chunk) instead of 800 m, so the loaded chunks past the fog are culled, not drawn.

## 0.1.0-dev

First version.

- `VoxelGameSpec` + `runVoxelGame`: a playable voxel game from one declaration.
- Mining, placing, an inventory and crafting screen, a HUD, first and third person.
- Keyboard and mouse, gamepad and touch controls.
- `InputMap` reads a finger as a gesture, not as a mouse button: one that lifts where it
  landed presses the primary or the secondary button (`touchTapPrimary`, the game's own
  "is a creature under the crosshair" bit), one that stays put for `mineDelay` holds the
  primary one until it lifts, and one that travels past `tapSlop` is the look and presses
  nothing. `touchMove`, `setTouchHeld` and `touchDigit` are the on-screen controls' half,
  read through the same `down` / `justPressed` / `axis(..., touch:)` / `digitPressed()`
  a key or a pad goes through. `VoxelGameWidget` forwards `onPointerCancel`, so a pointer
  the system takes away is dropped instead of left down.
- A one-shot press waits for the step that reads it. A frame that runs no simulation step
  no longer drains them, which above 60 fps threw away about half of every player's taps
  and clicks; and `VoxelGame.step` is now the single reader of the bag and pause buttons,
  so one press can no longer close a screen in one place and open another somewhere else.
- Mobs from `MobSpec`: rigs, gaits, drops, spawn rules and a brain of goals.
- `Goal` / `GoalSelector`: the goal system, usable with any creature class.
- Day and night sky, sounds, circuits (`SignalSpec`), liquids.
- Save slots, and hosting or joining a multiplayer world.
- Hooks: `onBlockBroken`, `onBlockPlaced`, `onMobKilled`, `onTick`, `GameSystem`.
- The package description and the dartdoc say what the kit does, not which game it was
  measured against: "a voxel sandbox in a few lines". The library's header names the
  three packages it sits on as they are called today.
