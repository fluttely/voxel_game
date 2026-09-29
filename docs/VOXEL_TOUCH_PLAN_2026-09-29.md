# The touch-controls plan (VT) — 2026-09-29

**Question.** The kit reads a finger on the world (look, mine, use) but draws no control
for the rest, so a game built on `voxel_game` cannot walk, jump or open its bag on a phone
(`CL-009`). What does the kit put on screen, and how does a touch on it stay out of the
world's gesture?

**Answer, in one line.** A `TouchControls` layer the kit owns (a floating stick, jump,
sneak, view, pause), a hotbar in `DefaultHud` that takes its own taps, and an `InputMap`
that knows which device spoke last and which touches a control claimed. Declared by a
`TouchControlsSpec` on `VoxelGameSpec`; shown only while the last input was a finger.

Closes `CL-009`, and gives `DefaultHud` the witness `CL-005` asks for (`VT2`).

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| VT1 `InputMap` — the last device, claimed touches, a toggle and a one-shot | **done** 2026-09-29: `InputDevice` + `InputMap.lastDevice` (starts `touch` on Android/iOS), `claimTouch` (the lift also drops any gesture state the finger had), `touchToggle` / `touchHeld` / `touchPress`; `_onPad` became the public `onPad` so a test can hand it a pad event. The plan's `clear` is `releaseKeys` in the code | `input_map_test.dart` covers the four; nothing on screen changes |
| VT2 `DefaultHud` — a hotbar a finger can use | todo | widget tests mount `DefaultHud` over a `VoxelGame`; a tap on a slot is never also a tap on the world; `CL-005` updated |
| VT3 `TouchControls` + `TouchControlsSpec` | todo | widget tests drive the stick, the rim, jump, sneak and the device switch; `CL-009` closed in the ledger |
| VT4 Seen on a phone | todo | the owner frees the S24 and plays it; **no benchmark**, just play |

Run every step on `opus 5.5:high` (a kit API that a game reads, and a pointer route that is
easy to get subtly wrong). VT4 needs no model: it is the owner holding the phone.

---

## What exists (read before VT1)

- `packages/voxel_game/lib/src/input/input_map.dart` already takes the whole *gesture*
  half: a touch on the world is a look drag, a hold that mines (`mineDelay`, 180 ms) or a
  tap that uses (`touchTapPrimary`). The on-screen half has its entry points and no caller:
  `touchMove(x, y)` (`:235`, the stick, read by `axis(..., touch:)`), `setTouchHeld(a, held)`
  (`:242`, a button; `true` also presses it for one step) and `touchDigit(i)` (`:252`).
  `clear` (`:222`) drops all of them when a screen opens.
- `packages/voxel_game/lib/src/ui/voxel_game_widget.dart:313-336`: **one `Listener`
  wraps the whole `Stack`** (world, HUD, inventory screen). A `Listener` is not in the
  gesture arena, so every pointer that hits anything in the stack reaches
  `InputMap.onPointerDown` too. The HUD is inside an `IgnorePointer` (`:331`), which is why
  nothing on it can be touched today.
- `packages/voxel_game/lib/src/ui/default_hud.dart`: crosshair, mining bar, hearts and the
  hotbar (44 dp slots, bottom centre), and the "Click to play — WASD…" hint while
  `!input.wantCapture`.
- `VoxelGame.step` (`packages/voxel_game/lib/src/core/voxel_game.dart:458-464`) is the one
  arbiter of `inventory` and `pause`: `inventory` opens the bag in gameplay, `pause` frees
  the capture (`input.release()`), and the next pointer down anywhere captures again
  (`voxel_game_widget.dart:317-319`). On a phone that is a pause: the world keeps stepping
  (rule 12), gameplay input stops, a tap resumes.
- `player_entity.dart:227`: `drop` is read with `justPressed`, one item a press.

## The layout

Landscape; everything inside `MediaQuery.paddingOf` (notch, punch-hole, gesture bar).

```
┌────────────────────────────────────────────────────────────────┐
│                                              [view]  [pause]   │
│                                                                │
│                              +                                 │
│                                                                │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ┐                                             │
│    stick zone                  ♥♥♥♥♥♥♥♥♥♥             [sneak]  │
│  │   (◯)         │                                             │
│   ─ ─ ─ ─ ─ ─ ─ ─     [1][2][3][4][5][6][7][8][9][⋯]  [ jump ] │
└────────────────────────────────────────────────────────────────┘
```

| Control | What it writes | Notes |
|:---|:---|:---|
| Stick, floating, in the lower-left zone | `touchMove(x, y)`; `(0, 0)` on the lift | Its centre is where the thumb lands; a radius of `stickRadius`. Pushed past `sprintAt` of the rim, it also holds `sprint` (`setTouchHeld(sprint, …)`), so running needs no button |
| Jump, bottom right | `setTouchHeld(jump, held)` while the finger is on it | Held also swims up and climbs, as the key does |
| Sneak, above jump | a **toggle** (`VTD2`): one tap on, one tap off | The state lives in `InputMap`, not in the button, so `clear` (a screen opening) turns it off and the button shows it |
| Hotbar slot (in `DefaultHud`) | a tap: `touchDigit(i)`; a hold on the **selected** slot: one `drop` (`VTD3`) | Taps only from `PointerDeviceKind.touch`; a mouse click over the hotbar is still the world's |
| `[⋯]` at the hotbar's end | one `inventory` | The bag closes through the screen's own close |
| View, top right | one `toggleView` | |
| Pause, top right | one `pause` | Frees the capture; the next touch resumes; the hint says "Tap to play" in touch mode |

`attack` and `use` have no button: the world is that button (`CL-003`).

## Decisions

| ID | Decision | Why |
|:---|:---|:---|
| VTD1 | **The hotbar takes its own taps; the kit publishes no hotbar geometry.** (Owner, 2026-09-29.) | `CL-009` proposed publishing the slot rects so controls could line up with them. That is the coupling that kept the app's `touch_controls.dart` pinned to `Hud.hotbarSlotRect`. A game with its own HUD calls `touchDigit` from its own hotbar. |
| VTD2 | **Sneak toggles**, set by `TouchControlsSpec.sneakToggles` (default true). (Owner.) | Holding sneak with the thumb that also looks cannot be done. |
| VTD3 | **Holding the selected slot drops one item**; no drop button. (Owner.) | The Bedrock gesture, and one button fewer on the right thumb's side. The hold time is `TouchControlsSpec.dropHold`. |
| VTD4 | **A control claims its touch; `InputMap` skips claimed pointers.** | The `Listener` over the stack sees every pointer (above). A control's own `Listener` sits deeper in the hit-test path, so its `onPointerDown` runs first and calls `input.claimTouch(e.pointer)`; `InputMap.onPointerDown` / `Move` / `Up` ignore a claimed pointer, and `Up` / `Cancel` forget the claim. Restructuring the stack so the world's `Listener` wraps only the `SceneView` was weighed and dropped: a hit-testable hotbar above the world would swallow mouse clicks under a locked cursor that rests over it. |
| VTD5 | **Stack order: world → `TouchControls` → HUD → screen.** | The HUD's hotbar sits above the stick's zone, so where the two overlap on a narrow phone, the slot wins, without either knowing the other's size. The HUD's passive pieces stay `IgnorePointer`, so the zone under them still takes the thumb. |
| VTD6 | **Touch mode is the last device that spoke.** `InputMap.lastDevice` (a new `InputDevice` enum: `keyboardMouse`, `gamepad`, `touch`), written by `onPointerDown` from `e.kind`, by `onKey`, and by `_onPad`. The controls and the hint read it through a `HudSelector`. | A Mac never sees the controls; a tablet with a keyboard switches on its own. Each handler writes from the event it was handed (rule 14). |
| VTD7 | **`TouchControlsSpec` on `VoxelGameSpec`**, `touchControls: TouchControlsSpec.standard` by default, `null` for a game that draws its own. `TouchControls` is public, so a game can put it over its own HUD. | Rule 7: the stick's radius, `sprintAt`, button size, `sneakToggles`, `dropHold` are fields, not constants in a widget. |

## Steps

### VT1 · `InputMap`: the last device, claimed touches, a toggle and a one-shot

`packages/voxel_game/lib/src/input/` only; nothing on screen changes.

- `InputDevice` enum (its own file, `input_device.dart`) and `InputMap.lastDevice`, written
  as `VTD6` says. A gamepad event counts only when it is a press or a stick past its dead
  zone, so a resting pad does not steal touch mode.
- `claimTouch(int pointer)` and the skip in the three touch paths (`VTD4`).
- `touchToggle(A action)`: flips a held action (the sneak button); `touchHeld(A action)`
  reads it for drawing. Both over the existing `_touchHeld`, so `clear` resets them.
- `touchPress(A action)`: a one-shot, pressed for one step and never held (drop,
  inventory, view, pause). `setTouchHeld(a, true)` then `false` gives the same today, but a
  name says what the controls mean.
- Tests in `test/input_map_test.dart`, one per behaviour: a claimed touch neither looks,
  mines nor taps; a toggle survives steps and dies with `clear`; a press is seen by exactly
  one step; each device sets `lastDevice`.
- `CHANGELOG.md` (voxel_game, `## Unreleased`).

### VT2 · `DefaultHud`: a hotbar a finger can use

- `voxel_game_widget.dart:331` stops wrapping the HUD in `IgnorePointer`; `DefaultHud`
  wraps its own passive pieces in it and leaves the hotbar hit-testable. A game's own
  `HudBuilder` that drew plain widgets is unaffected (the `Listener` over the stack sees
  pointers either way); one with gesture widgets on it now receives them. Say so in the
  `CHANGELOG` as **breaking**, with the one-line fix (wrap it in `IgnorePointer`).
- Each slot: a `Listener` that claims touch pointers (`VTD4`) and a
  `GestureDetector(supportedDevices: {PointerDeviceKind.touch})`: tap → `touchDigit(i)`;
  long press on the selected slot after `dropHold` → `touchPress(drop)`.
- `[⋯]` after the last slot, drawn only in touch mode: `touchPress(inventory)`.
- The hint: "Tap to play" when `lastDevice == touch`, the keyboard line otherwise.
- Widget tests (`test/default_hud_test.dart`): a tap on slot 3 selects it and the step sees
  no `use`; a hold on the selected slot drops one; a mouse click on a slot selects nothing;
  `[⋯]` opens the bag. This is the first test that mounts `DefaultHud`; update `CL-005`'s
  evidence in the ledger (the HUD is witnessed; `InventoryScreen` and the widget's wiring
  are still not), do not close it.

### VT3 · `TouchControls` and `TouchControlsSpec`

- `lib/src/spec/touch_controls_spec.dart`: `stickRadius`, `stickZone` (a fraction of the
  width and height from the bottom-left), `sprintAt`, `buttonSize`, `sneakToggles`,
  `dropHold`; `const TouchControlsSpec.standard`. Asserts on the ranges (rule 5).
- `VoxelGameSpec.touchControls` (nullable, defaults to `standard`). `DefaultHud` reads
  `dropHold` from it.
- `lib/src/ui/touch_controls.dart`: the stick zone, jump, sneak, view, pause, laid out by
  the spec inside the safe area. Every control claims its pointer. The stick reads only the
  event it was handed, its origin the pointer-down's position (rule 14).
- Mounted in `voxel_game_widget.dart` between the world and the HUD (`VTD5`), built only
  when `spec.touchControls != null`, and shown (`HudSelector`) only while
  `lastDevice == touch`, the game is in `gameplay` and no screen is open.
- Widget tests (`test/touch_controls_test.dart`): a drag in the zone moves the stick and
  turns no look; past the rim it sprints; the lift zeroes both; jump is held while pressed;
  sneak toggles and `clear` turns it off; a key event hides the layer, a touch shows it.
- `README.md`: the controls section says what a phone shows, and how to turn it off or
  reuse `TouchControls`. Ledger: close `CL-009`.

### VT4 · Seen on a phone

Only when the owner frees the Galaxy S24 (`CLAUDE.md`, benchmarks): `flutter run` the
example in debug or release, walk, run, jump, sneak off an edge, pick a slot, drop, open
the bag, pause and resume, look and mine with the other thumb at the same time. Nothing is
measured. What looks wrong becomes a `VT5` row here.

## Out of scope

- The app's own `touch_controls.dart` (in `poc_cubeworld/`, another repository): it keeps
  its layout; it can move onto `TouchControls` whenever it wants.
- Portrait: the example and the benchmark run landscape; a portrait layout is a later
  `TouchControlsSpec`, not a branch in the widget.
- `KL-004` (Windows and Linux get a drag instead of a locked mouse) is a mouse matter and
  stays open.
