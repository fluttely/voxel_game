# Music

This folder ships empty on purpose. Each biome group plays one track, looked up
here by a fixed name:

| File | Plays in | Until it exists, synthesised by `sound_recipes` |
|:---|:---|:---|
| `meadow.mp3` | ocean, beach, plains, forest, jungle | `StockMusic.pastoral` |
| `dunes.mp3` | desert | `StockMusic.arid` |
| `frost.mp3` | snow, mountains | `StockMusic.frozen` |
| `marsh.mp3` | swamp | `StockMusic.murky` |
| `deep.mp3` | underground (below y 40) | `StockMusic.cavern` |
| `underworld.mp3` | the underworld | `StockMusic.infernal` |

Drop a file with one of these names here and it plays in place of its score,
with no code change (`lib/src/game/music.dart`). Only commit music whose licence
allows it to be published with this open-source example.
