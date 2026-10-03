import 'dart:math' as math;

import 'package:voxel_game/voxel_game.dart';

/// The game's sounds: the kit's stock set, four of its own, its recorded
/// footsteps and its music.
///
/// A footstep is a take of four recorded in each kind of ground a block names
/// with its `step:` tag (`blockTable`): forest, desert, snow, swamp, and lava
/// for the hard ground.
///
/// The music is six tracks written as notes and synthesised at first play: the
/// meadow's wherever no other plays, by day and by night (the jungle's too),
/// its own in the desert, the snow and the swamp, the deep's underground and
/// the underworld's all through it. A recording dropped into
/// `assets/audio/music/` under a track's name plays instead.
final SoundSpec gameSounds = SoundSpec(
  recipes: {
    'break': SoundRecipe(
      0.18,
      (t, p, r) =>
          (r.nextDouble() * 2.0 - 1.0) * math.pow(1.0 - p, 2.0) * 0.8 + math.sin(t * 220.0 * _tau) * (1.0 - p) * 0.2,
    ),
    'place': SoundRecipe(0.10, (t, p, r) => math.sin(t * 180.0 * _tau) * math.pow(1.0 - p, 3.0) * 0.6),
    'bolt': SoundRecipe(
      0.3,
      (t, p, r) =>
          (math.sin(t * 200.0 * _tau) * math.sin(t * 37.0 * _tau) + (r.nextDouble() - 0.5) * 0.3) * (1.0 - p) * 0.5,
    ),
    'quest': SoundRecipe(0.5, (t, p, r) => math.sin(t * (p < 0.5 ? 523.0 : 784.0) * _tau) * (1.0 - p) * 0.4),
  },
  assets: {
    for (final kind in stepKinds)
      'step_$kind': [for (var i = 1; i <= 4; i++) 'assets/audio/footstep/$kind/${kind}_$i.wav'],
  },
  music: MusicSpec(
    tracks: {
      'meadow': MusicTrack(score: StockMusic.pastoral, asset: _music('meadow'), title: 'Meadow'),
      'dunes': MusicTrack(score: StockMusic.arid, asset: _music('dunes'), title: 'Dunes'),
      'frost': MusicTrack(score: StockMusic.frozen, asset: _music('frost'), title: 'Frost'),
      'marsh': MusicTrack(score: StockMusic.murky, asset: _music('marsh'), title: 'Marsh'),
      'deep': MusicTrack(score: StockMusic.cavern, asset: _music('deep'), title: 'Deep'),
      'underworld': MusicTrack(score: StockMusic.infernal, asset: _music('underworld'), title: 'Underworld'),
    },
    day: 'meadow',
    cave: 'deep',
    biomes: {'desert': 'dunes', 'snow': 'frost', 'mountain': 'frost', 'frozen_shore': 'frost', 'swamp': 'marsh'},
    dimensions: {'underworld': 'underworld'},
  ),
);

/// The kinds of ground with recorded footsteps, a folder each under
/// `assets/audio/footstep/`.
const List<String> stepKinds = ['forest', 'desert', 'snow', 'swamp', 'lava'];

const double _tau = math.pi * 2;

String _music(String track) => 'assets/audio/music/$track.mp3';
