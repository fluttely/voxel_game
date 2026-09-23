# The relayout — `packages/voxel_game/` becomes the kit's repository, the app is cut loose

**Step IDs: `VR0`–`VR5`.** Written 2026-09-21 at `7fd182ca`; **rewritten 2026-09-22** at
`e5b9a4b5`, before any file moved. Nothing in this plan changes behaviour: it moves files,
rewrites paths and renames things. Every gate is "the same suite, the same probe logs, the
same game".

The sibling plans are [`VOXEL_KIT_PLAN_2026-09-18.md`](./VOXEL_KIT_PLAN_2026-09-18.md) (how
the packages were extracted) and
[`VOXEL_CONSOLIDATION_PLAN_2026-09-19.md`](./VOXEL_CONSOLIDATION_PLAN_2026-09-19.md) (why
there are four). This one is the last structural move before the kit leaves: it gives
`packages/voxel_game/` the shape of the repository it will become, with the other three
packages inside it, and it takes the POC's vocabulary out of the kit's code.

### What the rewrite changed, and why

The first version (`e5b9a4b5`) turned this whole folder into `voxel_game` and moved the app
into a `demo/` beside it. That is not where the app is going. The app will leave for a
repository of its own, apart from the kit, and that move is a later conversation. So:

- **The app stays exactly where and what it is** — `poc_cubeworld/`, `cubeworld_poc`, its
  bundle ids, its save root. No `demo/`, no app rename, no save bill.
- **`voxel_game` stays at `packages/voxel_game/`** and becomes the root of the future kit
  repository: the workspace root, the published package, and the folder that holds the other
  three packages. Moving that one folder moves the whole kit.
- **The app is decoupled from the kit's workspace.** It stops being the workspace root and
  consumes the kit the way any outside project would, through one edge that is easy to cut.
- The old `VR2` (the demo's name) and `VR6` (renaming `poc_cubeworld/`) are gone. The rest —
  baseline, relayout, terms, docs, publish readiness — is kept, re-aimed at the new root.

## Progress

| Step | State | Gate |
|:---|:---|:---|
| VR0 The baseline, frozen before anything moves | **done** 2026-09-22 at `fadede2d`: analyze clean · 194 + 168 + 10 + 4 + 32 = **408 tests** · `--check` against `docs/baseline/` fails as s23 recorded (1512x900 @2x here, the logs were cut at 1600x900 @1x; the code is byte-identical to `f6155a18`), so the reference is HEAD's own raw logs on this Mac, recorded twice and stable between runs (stage31 15 lines, stage32 17, window 7) — VR1 diffs against those, not against `docs/baseline/` | the six suite commands green and `tool/probe_baseline.sh --check` clean, with the numbers written into this table's row |
| VR1 The relayout — the kit moves under `packages/voxel_game/`, the app leaves the workspace | **done** 2026-09-22: analyze clean in both trees · 194 + 32 + 168 + 10 + 4 = **408 tests** · no hosted package changed version in either lock (the kit's lost `flutter_soloud`/`hooks` as *direct* deps, the app's lost 25 hosted packages: `voxel_engine`'s dev dependency `test` and what it pulls — corrected in VR3, this row said 26) · the three probe logs identical to VR0's after the filter · a `--screenshot` of the relaid build shows the world, water, sky and HUD | analyze clean in both trees, the same test count, no hosted package changed version, probe logs match `docs/baseline/`, `flutter run -d macos` plays |
| VR2 The terms leave the kit's implementation | **done** 2026-09-22: 21 rewrites in the 19 files, the gate grep empty over tracked files and over the disk (build dirs and locks aside) · `terrain.shaderbundle` recompiled and byte-identical · 408 tests, probe logs identical to VR0's · the library header also stopped naming the pre-consolidation packages · `McBrightness` in `terrain.frag` kept its name (outside the grep, and renaming it changes the compiled bundle) | `grep -ri 'minecraft\|cube ?world\|\bpoc\b'` over every non-`.md` file under `packages/voxel_game/` returns nothing |
| VR3 The docs realigned to the two trees | **done** 2026-09-22: every markdown link in both `CLAUDE.md`s/`AGENTS.md`s, both `README.md`s, `ROADMAP.md`, `PUBLISHING.md`, both ledgers and the moved plans resolves; backticked paths in the current-state docs resolve (the plans' and the session log's old paths are history and stay) · the kit's `CLAUDE.md` renumbers the kit's rules 1–17 · its ledger holds `CL-005`/`008`/`009` and numbers new entries `KL-nnn` · its `README.md` install section now shows the four overrides a plain `path:` cannot replace · the app's `AGENTS.md` resynced to its `CLAUDE.md` | every path in both `CLAUDE.md`s, both `README.md`s, `ROADMAP.md`, `PUBLISHING.md` and the moved plans resolves |
| VR4 Publish readiness for the four packages | **done** 2026-09-23: MIT `LICENSE` (the repo root's text, `2026 kevinkobori`) in each · `homepage`/`repository`/`issue_tracker` on `github.com/fluttely/voxel_game` (the nested three at `tree/main/packages/<p>`) and five `topics` each · `0.1.0` everywhere, `^0.1.0` between the four, in both examples and in the app · `publish_to: none` only on the two examples · two descriptions trimmed under 180 characters · `.pubignore` also keeps out `CLAUDE.md`, `AGENTS.md`, `PUBLISHING.md`, `docs/`, `tool/` and repeats `.gitignore`'s lines · the nested three **cannot dry-run in place** (below), so `tool/publish_package.sh` runs them from a git-less copy · dry runs: `voxel_engine` 127 KB / 0 warnings, `sound_recipes` 7 KB / 0, `voxel_scene` 468 KB / 1, `voxel_game` 71 KB / 1 — the one warning is the exact `flutter_scene: 0.23.0` pin, kept by the developer's decision · every file list read · 408 tests, analyze clean in both trees | `pub publish --dry-run` green for `voxel_engine`, `sound_recipes`, `voxel_scene`, `voxel_game` |
| VR5 Ready to move — the kit folder stands alone | **done** 2026-09-23 at `2c3f2f34`: a copy of exactly the folder's 237 tracked files, taken outside the repository, resolved to a `pubspec.lock` identical to the in-tree one · analyze clean · 32 + 168 + 10 + 4 = **214 tests** · after `git init` in the copy (the kit's future home is a git repository), the four dry runs through `tool/publish_package.sh` gave the same archives and warnings as in-tree (127 KB / 0, 7 KB / 0, 468 KB / 1, 71 KB / 1 — the pin), and `pub publish` inside a nested package failed safe · the grep empty over tracked files and over the disk · every relative link in the kit's docs resolves in the copy · **the plan is closed; the folder is handed over** | a copy of `packages/voxel_game/` taken outside the repo resolves, analyzes, tests and dry-runs with nothing else beside it |

---

## The shape, before and after

Today `poc_cubeworld/` is the app **and** the workspace root, and the four packages are
siblings under its `packages/`. After VR1 the app is a plain Flutter project and the kit is
one folder that holds everything it needs.

```
poc_cubeworld/                      the app — name, bundle ids and save root unchanged
├── pubspec.yaml                    name: cubeworld_poc · no workspace: any more ·
│                                   dependency_overrides → the four packages by path
├── pubspec.lock                    the app's own (it was the whole workspace's)
├── lib/ test/ assets/ android/ ios/ macos/ flutter_scene_generated/
├── tool/                           probe_baseline.sh, perf_loop.sh — they drive the app
├── docs/                           the app's: baseline/, the Godot perf study, its ledger
├── ROADMAP.md  README.md  CLAUDE.md  AGENTS.md
└── packages/
    └── voxel_game/                 THE FUTURE KIT REPOSITORY — moved out whole in the end
        ├── pubspec.yaml            name: voxel_game · the workspace root · the published package
        ├── pubspec.lock            the kit workspace's lock
        ├── lib/ test/ example/     unchanged
        ├── README.md  CHANGELOG.md  analysis_options.yaml   unchanged in place
        ├── .pubignore              new — keeps packages/ and the build dirs out of the tarball
        ├── .gitignore              new — the kit must ignore its own build output once alone
        ├── CLAUDE.md  AGENTS.md    new — the kit's rules, lifted from the app's (VR3)
        ├── PUBLISHING.md           ← packages/PUBLISHING.md
        ├── docs/                   the kit's plans and its ledger (VR1, VR3)
        └── packages/
            ├── voxel_engine/       ← packages/voxel_engine
            ├── voxel_scene/        ← packages/voxel_scene (its example stays under it)
            └── sound_recipes/      ← packages/sound_recipes
```

`poc_cubeworld/packages/` ends up holding only `voxel_game/`. `voxel_scene/example` and
`voxel_game/example` stay `publish_to: none` apps, as before.

### The decisions behind that shape (taken 2026-09-22, do not re-litigate)

1. **The kit's root is the package, not a wrapper.** The kit is the product. A published
   `repository:` should point at a tree whose root is the thing you installed — so the
   future repository's root is `voxel_game`, and the three packages it depends on hang
   under its `packages/`. They go together because they version together: every breaking
   change in `voxel_engine` is a release of `voxel_scene` and `voxel_game` too
   (`PUBLISHING.md` §The version graph). Being on pub.dev separately does not change that.
2. **The app is a consumer, not a member.** It leaves the workspace and reaches the kit
   through `dependency_overrides` with `path:` entries — the same edge any outside project
   has, and the only edge that must be cut or replaced on the day the kit leaves. A nested
   workspace (the app's workspace containing the kit's) would keep the two coupled in one
   resolution; that is exactly what this plan removes.
3. **Everything the kit owns moves inside its folder** — `PUBLISHING.md`, the three plans
   that record how it was extracted, this plan, its ledger entries, a rules file of its own.
   **Everything the app owns stays with the app** — `ROADMAP.md` (a Flutter asset the
   credits read at runtime), `tool/`, `docs/baseline/`, the Godot performance study.
4. **"cubeworld", "poc" and "minecraft" leave the kit's code and stay everywhere else.**
   `voxel_game`'s dartdoc is published; it should describe what the code does, not which
   game it was measured against. They keep their place in `.md` files (the lineage) and in
   the app, which *is* the POC and keeps its name until its own move is discussed.
5. **No save bill.** The app's name, bundle ids and save root
   (`…/com.remottely.cubeworldPoc/dawnforge_cubeworld_poc/worlds/`) do not change, so the
   worlds on this machine and the byte-level parity with the Godot POC both survive.
6. **The move itself is not a step.** The plan ends when the folder is ready to leave
   (VR5). Moving it into the new repository is done by the developer; what the app does
   once it is gone is the next conversation, not this plan (§After the move).

---

## What was verified before writing this

On 2026-09-21, at `7fd182ca`:

- **A workspace root can be published.** A throwaway workspace (`ws_root_probe` with one
  member) passed `dart pub publish --dry-run` with its `workspace:` key in place; the only
  warning was about the changelog. So `voxel_game` being both the workspace root and the
  published package is not a contradiction. Residual risk: pub.dev "may enforce additional
  checks" that a local dry run does not. Fallback if the server refuses, in order of
  preference: publish from a clean copy of the tree with the `workspace:` key removed, or
  drop the workspace entirely and give the examples `path:` dependencies.
- **A nested package is bundled unless it is ignored.** The same probe shipped its member's
  `lib/` and `pubspec.yaml` inside the tarball. A root `.pubignore` naming `packages/`,
  `build/`, `.dart_tool/`, `example/macos/` and `example/build/` removed them — the archive
  came back down to `lib/`, `README`, `CHANGELOG`, `LICENSE`, `pubspec.yaml`.
  **`.pubignore` is not optional in this layout**; without it every release of `voxel_game`
  ships the other three packages as dead weight. *(Corrected in VR4: that probe did not
  dry-run the member. Inside a git repository the same line hides the member from its own
  publish — see VR4 §As run.)*
- **The parent repo does not resolve this tree.** `../pubspec.yaml` (the 2D track) declares
  no workspace covering `poc_cubeworld/`, so the relayout cannot break the 2D project's
  resolution.

On 2026-09-22, at `e5b9a4b5`:

- **An app outside a workspace can consume a workspace nested inside its own folder.** A
  throwaway tree (`app/` with `app/packages/kit/` as a workspace root and
  `app/packages/kit/packages/eng/` as its member, `resolution: workspace`) resolved both
  ways: `dart pub get` inside `kit/` wrote a `workspace_ref.json` in `eng/` pointing at
  `kit/`, not at `app/`; and `app/` ran code from both packages.
- **…but only through `dependency_overrides`.** With plain `path:` dependencies the app's
  resolution fails: `kit` asks for `eng: ^0.0.0` from *hosted*, the app offers `eng` from
  *path*, and pub refuses the two sources. Overriding all four packages by path is what
  works — and it is also what keeps working unchanged after VR4 swaps the `^0.0.0`s for
  real ranges.
- **The kit is already self-contained.** Nothing under `packages/` reaches outside it except
  `PUBLISHING.md`'s link to `../docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md` and its prose
  naming `poc_cubeworld` — both moved or rewritten in VR1/VR3. The `../../Flutter/…`
  includes in the examples' `xcconfig`s are internal to each example.
- **The surface of the terms**: 19 tracked non-`.md` files under `packages/` still say
  `minecraft`, `cube world` or `poc` — doc comments in 13 `lib/src/` files, one test comment,
  the `voxel_game` pubspec's description, its example's pubspec and `main.dart`, and
  `voxel_scene/shaders/terrain.frag`.

---

## The steps

### VR0 — freeze the baseline

No file moves. Run, from today's root, and write the results into the Progress table:

```sh
flutter analyze && flutter test
cd packages/voxel_engine  && dart test
cd packages/voxel_scene   && flutter test
cd packages/sound_recipes && flutter test
cd packages/voxel_game    && flutter test
tool/probe_baseline.sh --check
```

Expected at `f6155a18`: analyze clean · 194 + 168 + 10 + 4 + 32 = **408 tests** · probe logs
match. Keep a copy of today's `pubspec.lock` in the scratchpad: VR1 compares against it.

**As run (2026-09-22):** the counts matched; the probe did not, for a reason that is not in
the tree. `docs/baseline/` was recorded on a 1600x900 @1x window and this Mac renders
1512x900 @2x, which moves the camera-settle and site lines (and the stage 32 footsteps line
is compared on one side only: its current wording carries `0.35 s`, which the filter drops).
So the gate is the one s23 used — this tree against unmodified HEAD on the same machine. A
copy of `tool/probe_baseline.sh` with its output directory redirected wrote HEAD's raw logs
into the scratchpad twice; the two runs were identical after the script's own filter. VR1's
probe gate is a third run of that copy on the relaid tree, diffed the same way.

### VR1 — the relayout (one commit; the tree is unbuildable between its halves)

`git status --short` first — move only the tracked paths listed, never a file somebody else
has in flight.

1. `git mv packages/voxel_engine packages/voxel_scene packages/sound_recipes packages/voxel_game/packages/`
   and `git mv packages/PUBLISHING.md packages/voxel_game/`.
2. `git mv` into `packages/voxel_game/docs/`: `VOXEL_PACKAGES_PLAN_2026-09-14.md`,
   `VOXEL_KIT_PLAN_2026-09-18.md`, `VOXEL_CONSOLIDATION_PLAN_2026-09-19.md` and this plan.
   `PERFORMANCE_VS_GODOT_2026-09-11.md`, `LEDGER.md` and `baseline/` stay in `docs/`.
3. `packages/voxel_game/pubspec.yaml`: drop `resolution: workspace` (a root does not resolve
   into another workspace) and add
   `workspace: [packages/sound_recipes, packages/voxel_engine, packages/voxel_scene, packages/voxel_scene/example, example]`.
   The three moved packages and the two examples keep `resolution: workspace` — their root
   is now `packages/voxel_game/`.
4. `poc_cubeworld/pubspec.yaml`: delete the `workspace:` block (and its comment), keep the
   four `^0.0.0` dependencies as they are, and add
   ```yaml
   # The kit is not part of this project's resolution: it is consumed by path, the one
   # edge that changes when packages/voxel_game/ leaves for its own repository.
   dependency_overrides:
     voxel_game:    {path: packages/voxel_game}
     voxel_engine:  {path: packages/voxel_game/packages/voxel_engine}
     voxel_scene:   {path: packages/voxel_game/packages/voxel_scene}
     sound_recipes: {path: packages/voxel_game/packages/sound_recipes}
   ```
5. **The locks.** Copy the current `pubspec.lock` to `packages/voxel_game/pubspec.lock` before
   the first `pub get`, so both resolutions start from the pinned versions instead of the
   newest ones. After `pub get`, diff both locks against VR0's copy: a hosted package may
   *disappear* from one of them (the app no longer resolves the examples' dependencies),
   none may change version.
6. New `packages/voxel_game/.pubignore` (as verified above: `packages/`, `build/`,
   `.dart_tool/`, `example/macos/`, `example/build/`) and `packages/voxel_game/.gitignore`
   (`build/`, `.dart_tool/`, `.flutter-plugins-dependencies`, `**/doc/api/`, `.idea/`,
   `*.iml`, `.DS_Store`). The app's `.gitignore` line `packages/*/build/` becomes redundant
   and goes.
7. `flutter clean` in the app and in every package (`build/` and `.dart_tool/` hold absolute
   paths, and every package moved one level down), then `flutter pub get` in
   `packages/voxel_game/` **and** in `poc_cubeworld/`, then the suite from the new
   directories, then `tool/probe_baseline.sh --check`.

The suite from VR1 on:

```sh
flutter analyze && flutter test                               # the app
cd packages/voxel_game                  && flutter analyze && flutter test
cd packages/voxel_game/packages/voxel_engine  && dart test
cd packages/voxel_game/packages/voxel_scene   && flutter test
cd packages/voxel_game/packages/sound_recipes && flutter test
```

**Gate:** analyze clean in both trees, 408 tests, no hosted package changed version, probe
logs identical, and `flutter run -d macos` plays. Rule 18: a screenshot probe is what closes
this step, not the tests. The shaders need no rebuild — `terrain.shaderbundle` moves as a
file and its `packages/voxel_scene/…` asset key does not depend on where the package sits.

### VR2 — the terms leave the kit's implementation

Rewrite, do not delete: a comment that says *why* the number is what it is keeps its
reasoning and loses the trademark. `/// Minecraft's view bobbing: the eye drops by |cos|…`
becomes `/// View bobbing: the eye drops by |cos|…`. Scope: every non-`.md` file under
`packages/voxel_game/` — the 19 found above:

- **Doc comments** in `lib/` of all four packages (13 files under `lib/src/`), one comment in
  `voxel_engine/test/core/physics/physics_test.dart`, and
  `packages/voxel_scene/shaders/terrain.frag` (a shader comment changes no bytes of the
  compiled bundle, so no rebuild).
- **`voxel_game`'s `pubspec.yaml` and `lib/voxel_game.dart`** both open with "A
  Minecraft-like in a few lines" — that is the package's pub.dev description; it is rewritten
  to say what it is ("a voxel sandbox in a few lines"). Same for `example/pubspec.yaml` and
  `example/lib/main.dart`.

**The app is out of scope.** `lib/`, its screens (`'CUBEWORLD POC'` on the credits, the title
screen's tagline), its native config and its tests keep every word — it is the POC. `.md`
files are untouched too: the packages' `CHANGELOG.md`s and the plans are the lineage.

### VR3 — the docs realigned to the two trees

- **The kit gets its own rules**: `packages/voxel_game/CLAUDE.md` (and `AGENTS.md`, the same
  text, as the app keeps the pair). It carries the kit half of today's `CLAUDE.md` — rules 1–
  14, 17, 20, 21, the packages' testing policy, the commit and parallel-session customs — with
  every path rewritten from the kit's root and without anything that only makes sense next to
  the app (§Two codebases, rule 15's block table and Godot parity, rule 18's probes, the
  `ROADMAP.md` duties). It must read correctly the day it is the root of its own repository.
- **The kit's ledger**: `packages/voxel_game/docs/LEDGER.md` takes `CL-005`, `CL-008` and
  `CL-009` — the entries about the kit's surface and its plans — with their IDs kept, so
  every reference to them still resolves by name. `CL-004`, `CL-006`, `CL-007` (the app and
  the kit side by side) and the closed ones stay in the app's; each moved entry leaves a
  one-line pointer behind.
- **`packages/voxel_game/README.md`** adds the four-package graph and a "working on the kit"
  section (the suite commands above, from the kit's root). **`PUBLISHING.md`**: the workspace
  root is now its own folder, `.pubignore` is a requirement, the release commands run from
  `packages/<p>` and `.`, the link to the consolidation plan becomes `docs/…`, and "a
  repository of its own" becomes the next thing that happens instead of a wish.
- **The app's `CLAUDE.md` and `AGENTS.md`** (the latter still says 381 tests at `b0b94ebd` —
  resynced here): the map table, the package graph section ("resolved through the pub
  workspace declared in `pubspec.yaml`" is no longer true — the kit is its own workspace,
  consumed by path overrides), the suite commands, rule 17's shader path, and a line saying
  that `packages/voxel_game/` is governed by its own `CLAUDE.md`.
- **The app's `README.md`**: the kit's paths. **`ROADMAP.md`**: links to the moved plans
  (`packages/voxel_game/docs/…`) and a §Session log entry for the step.
- The moved plans' own relative links (`./VOXEL_KIT_PLAN_…` between themselves keep working;
  anything pointing at `../lib/…`, `ROADMAP.md` or `docs/baseline/` is the app's and is
  rewritten as prose, since those links break on the move).

### VR4 — publish readiness

Exactly `PUBLISHING.md`'s checklist, now unblocked: a `LICENSE` in each of the four,
`homepage`/`repository`/`issue_tracker`/`topics` in each pubspec, real version ranges instead
of `^0.0.0`, `0.1.0` as the first number, `publish_to: none` removed from the four and kept
on the two example apps. Then the four dry runs, in dependency order, reading each file list
(the `.pubignore` guard). `voxel_game` cannot be released before the three it depends on exist
on pub.dev.

**Found in VR3, for this step:** VR3 put `CLAUDE.md`, `AGENTS.md` and `docs/` (the plans and
the ledger) at the kit's root, beside `PUBLISHING.md`, and today's `.pubignore` names none of
them — so `voxel_game`'s tarball would ship the kit's rules, its four plans and its ledger.
Decide what the package carries before the dry run, and read its file list against it.

**One input is the developer's, not the plan's:** the new repository's URL, which fills
`repository`, `homepage` and `issue_tracker`, and the license. Ask for both when this step
opens; do not guess them. The app's overrides need no change — they already win over any
version range.

**As run (2026-09-23).** The developer chose MIT and `https://github.com/fluttely/voxel_game`.
The first dry run, `voxel_engine`'s, came back with an archive under 1 KB and "the pubspec
is hidden". **Inside a git repository pub applies the ignore files of every folder from the
git root down to the package**, so the kit's `packages/` line hides each nested package from
itself, and a nested `.pubignore` (`!*`, `!**`) cannot re-include it. A scratch probe showed
both sides: the same tree in a `git init`-ed folder fails, and with no `.git` it publishes.
That is why §What was verified passed on 2026-09-21. It will stay true in the kit's own
repository. Decision 1 stands. The fix is the fallback this plan already named: publish
from a clean copy, only for the three nested packages. `tool/publish_package.sh` copies
the folder without `.git`, `build/` and `.dart_tool/`, resolves the workspace there, and
publishes from `packages/<p>`. `voxel_game` publishes in place, where its `.pubignore` is
needed. Running `pub publish` inside a nested package by mistake fails safe.
The four READMEs (the pub.dev pages) now install with `^0.1.0`. `voxel_scene` and
`voxel_game` keep `flutter_scene: 0.23.0` exact: the developer accepted pub's warning over
loosening a pin that guards a private import (`PUBLISHING.md` §Releasing). `voxel_scene`'s
tarball also carries its example's `macos/` (about 35 KB); an example's native project is
normal content for a package.

### VR5 — ready to move

Prove the folder stands alone by doing to a copy exactly what the move will do to it:

```sh
rsync -a --exclude build --exclude .dart_tool packages/voxel_game/ "$SCRATCH/voxel_game/"
cd "$SCRATCH/voxel_game" && flutter pub get && flutter analyze && flutter test
# … the three packages' tests, and the four publish dry runs
```

and `grep -rn 'poc_cubeworld\|cubeworld_poc\|\.\./\.\./\.\.' packages/voxel_game` over
non-`.md` files returns nothing. Then the step is closed and the folder is handed over.

**As run (2026-09-23).** The copy was stricter than the `rsync` above. It took exactly
`git ls-files` (237 files), because an `rsync` of the disk also carries untracked local
state (`.flutter-plugins-dependencies`, the examples' `ephemeral/`), and the new repository
will receive none of it. The dry runs ran after a `git init` in the copy: the kit will
live in a git repository, and that is where VR4's parent-ignore trap applies. Both gates
held; numbers in the Progress row. The kit's `CLAUDE.md` names `poc_cubeworld` and
Dawnforge only under "while it still lives inside…", which reads correctly from either
place. The
move itself — and whether it carries history (`git subtree split
--prefix=poc_cubeworld/packages/voxel_game` keeps only the history under the new path; the
extraction commits before VR1 stay here) — is the developer's.

---

## After the move — not planned here

Written down so nobody is surprised, and so the next conversation starts from it:

- **The app stops resolving** the moment `packages/voxel_game/` leaves: its four
  `dependency_overrides` point at a folder that is gone. The replacement is one of: a `git:`
  dependency on the new repository (`PUBLISHING.md` §The step before publishing), a path to a
  sibling checkout, or pub.dev ranges once VR4's releases exist. Choosing is part of the app's
  own move.
- The app's links into `packages/voxel_game/docs/` break with it; they become links into the
  new repository.
- `docs/baseline/` and `tool/probe_baseline.sh` stay with the app — they are the app's
  evidence. The kit's out-of-the-box surface still has no witness of its own (`CL-005`).

---

## Risks, and what each one costs

| Risk | Cost | Guard |
|:---|:---|:---|
| pub.dev refuses a pubspec carrying `workspace:` | `voxel_game` cannot be released from this tree | verified green on a local dry run; two fallbacks written above |
| `.pubignore` forgotten | every release of `voxel_game` ships the other three packages | VR4's dry run prints the file list — read it |
| The app's first `pub get` outside the workspace picks newer hosted versions | a behaviour change hidden inside a file move | both locks seeded from VR0's copy; VR1's gate diffs them |
| Plain `path:` dependencies instead of overrides | the app does not resolve at all | verified: only `dependency_overrides` works; written into VR1 |
| Stale `build/` and `.dart_tool/` after the move | a build that fails for a reason that is not in the diff | `flutter clean` everywhere is part of VR1 |
| Another session holding uncommitted work in this tree | a `git mv` that eats somebody's file | `git status --short` before VR1; move only the tracked paths listed |
| The kit's rules file still assumes the app beside it | the new repository's first session follows rules about files it does not have | VR3 writes it from the kit's root; VR5 reads it from the copy |
| Something in the kit reaches outside its folder | the kit breaks only after the move, where nobody is looking | VR5 builds a copy with nothing beside it |
