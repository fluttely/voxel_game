import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import 'rig_animator.dart';

/// The body plans of the stock rigs.
enum RigKind {
  /// Two legs, two arms, a head: a zombie, a villager, the player.
  humanoid,

  /// Four legs, a barrel, a head and a tail: a cow, a horse, a wolf.
  quadruped,

  /// One squashy block: a slime.
  blob,

  /// A body and eight legs.
  spider,

  /// A body, a head, two wings and two legs: a chicken, a parrot.
  bird,
}

Vector3 _rgb(int c) => Vector3(((c >> 16) & 0xFF) / 255.0, ((c >> 8) & 0xFF) / 255.0, (c & 0xFF) / 255.0);

/// A creature's look, declared: one of the stock body plans in its colours.
/// It is fitted to the creature's collider when built.
class Rig {
  /// A humanoid in [skin], [shirt] and [pants]; [armsForward] holds the arms
  /// out in front (the walk everyone reads as a zombie); [redEyes] for the
  /// hostile.
  const Rig.humanoid({
    this._skin = 0xE8B890,
    this._shirt = 0x3A6EA5,
    this._pants = 0x3C4F80,
    this.armsForward = false,
    this.redEyes = false,
  }) : kind = RigKind.humanoid,
       colors = const [];

  /// A four-legged animal: a [body] colour and a [head] (and legs) colour.
  const Rig.quadruped({int body = 0x8A6A4A, int? head})
    : kind = RigKind.quadruped,
      colors = const [],
      armsForward = false,
      redEyes = false,
      _skin = body,
      _shirt = head ?? body,
      _pants = 0;

  /// A slime.
  const Rig.blob({int color = 0x6CC24A})
    : kind = RigKind.blob,
      colors = const [],
      armsForward = false,
      redEyes = false,
      _skin = color,
      _shirt = color,
      _pants = 0;

  /// A spider: a [body] and its [eyes].
  const Rig.spider({int body = 0x3A3030, int eyes = 0xD02020})
    : kind = RigKind.spider,
      colors = const [],
      armsForward = false,
      redEyes = false,
      _skin = body,
      _shirt = eyes,
      _pants = 0;

  /// A bird: a [body] and its [feathers] (wing tips, tail, comb).
  const Rig.bird({int body = 0xF0F0F0, int feathers = 0xD03030})
    : kind = RigKind.bird,
      colors = const [],
      armsForward = false,
      redEyes = false,
      _skin = body,
      _shirt = feathers,
      _pants = 0;

  /// The body plan.
  final RigKind kind;

  /// Reserved for rigs with more colours.
  final List<int> colors;

  /// Humanoid arms held out in front.
  final bool armsForward;

  /// Red eyes.
  final bool redEyes;

  final int _skin, _shirt, _pants;

  /// The main colour, `0xRRGGBB`: a humanoid's skin, an animal's body.
  int get skinColor => _skin;

  /// Builds this rig for a collider [halfWidth] wide and [height] tall: its
  /// own nodes over the [RigModel] every rig of this look and size shares.
  RigInstance build(double halfWidth, double height) => RigInstance._(RigModel.of(this, halfWidth, height));

  // A look is its values: two species declared with the same one share a model.
  @override
  bool operator ==(Object other) =>
      other is Rig &&
      other.kind == kind &&
      other._skin == _skin &&
      other._shirt == _shirt &&
      other._pants == _pants &&
      other.armsForward == armsForward &&
      other.redEyes == redEyes &&
      _sameColors(other.colors, colors);

  @override
  int get hashCode => Object.hash(kind, _skin, _shirt, _pants, armsForward, redEyes, Object.hashAll(colors));
}

bool _sameColors(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The voxels of one piece of a [RigModel], and its mesh, made the first time
/// a rig of it is drawn. Parts cut from the same voxels (a humanoid's two legs)
/// share one.
class RigShape {
  RigShape._(this.voxels, this.scale, this.origin, this.shrink);

  /// The piece, in voxels.
  final Map<IVec3, Vector3> voxels;

  /// Metres a voxel.
  final double scale;

  /// The voxel the part pivots on.
  final Vector3 origin;

  /// The mesh's scale under its pivot: a narrow limb pulled in off its
  /// neighbours' faces.
  final Vector3 shrink;

  /// The mesh, one for every creature drawn with this shape; null for an
  /// empty piece.
  late final MeshGeometry? geometry = VoxelModelMesh.geometry(voxels, scale, origin);
}

/// A posable part of a [RigModel]: its [shape], where it rests and how it
/// starts.
class RigModelPart {
  RigModelPart._(this.name, this.shape, this.base, {this.sx = 1.0, this.ry = 0.0});

  /// The name its [RigPart] goes by (see [RigInstance.parts]).
  final String name;

  /// What it draws.
  final RigShape shape;

  /// The rest position of its pivot.
  final Vector3 base;

  /// Its scale along x at rest (-1: a mirrored spider leg).
  final double sx;

  /// Its yaw at rest (a spider leg's splay).
  final double ry;
}

/// A [Rig] fitted to one collider: the parts and meshes every creature of that
/// look and size shares, built once ([of]). A [RigInstance] hangs its own
/// posable nodes on them, so flutter_scene draws each part of a species once a
/// pass, instanced over the creatures, instead of once a creature.
class RigModel {
  RigModel._(this.rig, this.halfWidth, this.height) {
    _build();
  }

  /// The model of [rig] at a collider [halfWidth] wide and [height] tall: the
  /// same object for every call with the same look and size.
  factory RigModel.of(Rig rig, double halfWidth, double height) =>
      _built[(rig, halfWidth, height)] ??= RigModel._(rig, halfWidth, height);

  static final Map<(Rig, double, double), RigModel> _built = {};

  /// The look.
  final Rig rig;

  /// The collider it was fitted to.
  final double halfWidth, height;

  /// The parts, in the order they are built.
  final List<RigModelPart> parts = [];

  /// A spider's resting splay, a leg at a time.
  final List<double> legFan = [];

  /// The saddle line of a quadruped (metres above the feet), 0 otherwise.
  double get backHeight => _backHeight;
  double _backHeight = 0.0;

  /// The scale that brings the authored body inside its collider (1 when it fits).
  double get fit => _fit;
  double _fit = 1.0;

  double _top = 0.0;
  final Map<(Map<IVec3, Vector3>, bool), RigShape> _shapes = {};

  void _part(
    String name,
    Map<IVec3, Vector3> voxels,
    Vector3 at,
    double s, {
    bool narrow = false,
    double sx = 1.0,
    double ry = 0.0,
  }) {
    final lo = Vector3.all(double.infinity), hi = Vector3.all(double.negativeInfinity);
    for (final k in voxels.keys) {
      final v = Vector3(k.x.toDouble(), k.y.toDouble(), k.z.toDouble());
      Vector3.min(lo, v, lo);
      Vector3.max(hi, v + Vector3.all(1.0), hi);
    }
    final origin = Vector3.zero();
    final base = at.clone();
    final shrink = Vector3.all(1.0);
    if (narrow) {
      origin
        ..x = (lo.x + hi.x) * 0.5
        ..z = (lo.z + hi.z) * 0.5;
      base
        ..x += origin.x * s
        ..z += origin.z * s;
      shrink
        ..x = 1.0 - 0.02 / ((hi.x - lo.x) * s)
        ..z = 1.0 - 0.02 / ((hi.z - lo.z) * s);
    }
    final shape = _shapes[(voxels, narrow)] ??= RigShape._(voxels, s, origin, shrink);
    parts.add(RigModelPart._(name, shape, base, sx: sx, ry: ry));
    _top = math.max(_top, at.y + (hi.y - origin.y) * s);
  }

  void _build() {
    final skin = _rgb(rig._skin), shirt = _rgb(rig._shirt), pants = _rgb(rig._pants);
    final dark = Vector3(0.05, 0.05, 0.05);
    final s = rig.kind == RigKind.humanoid ? 0.055 * (height / 1.75) : 0.06;
    switch (rig.kind) {
      case RigKind.quadruped:
        final bodyLen = (height * 14).toInt(), bodyH = (height * 7).toInt(), bodyW = (halfWidth * 22).toInt();
        final legH = (height * 6).toInt();
        var v = <IVec3, Vector3>{};
        VoxelModel.box(v, IVec3(-bodyW ~/ 2, 0, -bodyLen ~/ 2), IVec3(bodyW ~/ 2, bodyH, bodyLen ~/ 2), skin);
        _part('body', v, Vector3(0, legH * s, 0), s);
        _backHeight = (legH + bodyH) * s;
        v = {};
        final hs = (bodyW * 0.7).toInt();
        VoxelModel.box(v, IVec3(-hs ~/ 2, -hs ~/ 2, -hs), IVec3(hs ~/ 2, hs ~/ 2, 0), shirt);
        v[IVec3(-hs ~/ 2 + 1, 0, -hs)] = dark;
        v[IVec3(hs ~/ 2 - 1, 0, -hs)] = dark;
        _part('head', v, Vector3(0, (legH + bodyH * 0.8) * s, -bodyLen / 2 * s), s);
        final leg = <IVec3, Vector3>{};
        VoxelModel.box(leg, IVec3(-1, -legH, -1), const IVec3(1, 0, 1), shirt);
        for (var i = 0; i < 4; i++) {
          final lx = (bodyW / 2 - 1.5) * s * (i % 2 == 0 ? 1 : -1);
          final lz = (bodyLen / 2 - 2) * s * (i < 2 ? 1 : -1);
          _part('leg$i', leg, Vector3(lx, legH * s, lz), s, narrow: true);
        }
        v = {};
        final tailLen = math.max(bodyLen ~/ 3, 3);
        VoxelModel.box(v, IVec3(-1, -tailLen, 0), const IVec3(0, 0, 1), shirt);
        _part('tail', v, Vector3(0, (legH + bodyH * 0.85) * s, (bodyLen ~/ 2 + 1) * s + 0.01), s);
      case RigKind.humanoid:
        final k = height / 1.75;
        var v = <IVec3, Vector3>{};
        VoxelModel.box(v, const IVec3(-2, -12, -2), const IVec3(1, -1, 1), pants);
        _part('leg0', v, Vector3(-0.11 * k, 0.66 * k, 0), s);
        _part('leg1', v, Vector3(0.11 * k, 0.66 * k, 0), s);
        v = {};
        VoxelModel.box(v, const IVec3(-4, 0, -2), const IVec3(3, 11, 1), shirt);
        _part('body', v, Vector3(0, 0.66 * k, 0), s);
        v = {};
        VoxelModel.box(v, const IVec3(-2, -12, -2), const IVec3(1, -1, 1), skin);
        _part('arm0', v, Vector3(-0.345 * k, 1.30 * k, 0), s);
        _part('arm1', v, Vector3(0.345 * k, 1.30 * k, 0), s);
        v = {};
        VoxelModel.box(v, const IVec3(-4, 0, -4), const IVec3(3, 7, 3), skin, 0.04);
        final eye = rig.redEyes ? Vector3(0.9, 0.1, 0.1) : dark;
        v[const IVec3(-3, 4, -4)] = eye;
        v[const IVec3(2, 4, -4)] = eye;
        _part('head', v, Vector3(0, 1.32 * k, 0), s);
      case RigKind.blob:
        final v = <IVec3, Vector3>{};
        final r = (halfWidth * 16).toInt(), h = (height * 14).toInt();
        VoxelModel.box(v, IVec3(-r, 0, -r), IVec3(r, h, r), skin, 0.08);
        for (var x = -r; x <= r; x++) {
          for (var z = -r; z <= r; z++) {
            if (x.abs() == r || z.abs() == r) v.remove(IVec3(x, h, z));
            if (x.abs() == r && z.abs() == r) v.remove(IVec3(x, 0, z));
          }
        }
        v[IVec3(-r ~/ 2, h * 2 ~/ 3, -r)] = dark;
        v[IVec3(r ~/ 2, h * 2 ~/ 3, -r)] = dark;
        _part('body', v, Vector3.zero(), s);
      case RigKind.spider:
        var v = <IVec3, Vector3>{};
        VoxelModel.box(v, const IVec3(-4, 0, -3), const IVec3(4, 4, 5), skin, 0.06);
        VoxelModel.box(v, const IVec3(-3, 0, -7), const IVec3(3, 3, -3), skin * 0.9, 0.06);
        for (final e in const [IVec3(-2, 3, -7), IVec3(2, 3, -7), IVec3(-1, 2, -7), IVec3(1, 2, -7)]) {
          v[e] = shirt;
        }
        _part('body', v, Vector3(0, 0.35, 0), s);
        for (var i = 0; i < 8; i++) {
          v = {};
          final side = i % 2 == 0 ? 1 : -1;
          VoxelModel.box(v, IVec3.zero, const IVec3(5, 0, 0), skin);
          VoxelModel.box(v, const IVec3(5, -5, 0), const IVec3(5, 0, 0), skin);
          final fan = (i ~/ 2 - 1.5) * 0.3 * side;
          _part('leg$i', v, Vector3(side * 0.25, 0.42, (i ~/ 2 - 1.5) * 0.18), s, sx: side.toDouble(), ry: fan);
          legFan.add(fan);
        }
      case RigKind.bird:
        var v = <IVec3, Vector3>{};
        final beak = Vector3(0.95, 0.7, 0.2);
        VoxelModel.box(v, const IVec3(-2, 0, -3), const IVec3(2, 4, 3), skin);
        _part('body', v, Vector3(0, 0.25, 0), s);
        v = {};
        VoxelModel.box(v, const IVec3(-1, 0, -2), const IVec3(1, 3, 1), skin);
        VoxelModel.box(v, const IVec3(0, 1, -3), const IVec3(0, 1, -3), beak);
        VoxelModel.box(v, const IVec3(0, 3, -1), const IVec3(0, 4, -1), shirt);
        _part('head', v, Vector3(0, 0.5, -0.18), s);
        final wing = <IVec3, Vector3>{};
        VoxelModel.box(wing, const IVec3(0, 0, -2), const IVec3(3, 0, 2), skin);
        VoxelModel.box(wing, const IVec3(4, 0, -1), const IVec3(5, 0, 2), shirt);
        VoxelModel.box(wing, const IVec3(6, 0, 0), const IVec3(7, 0, 2), shirt);
        _part('wing1', wing, Vector3(0.18, 0.44, 0.0), s);
        _part('wing0', VoxelModel.mirrorX(wing), Vector3(-0.12, 0.44, 0.0), s);
        v = {};
        VoxelModel.box(v, const IVec3(-1, 0, 0), const IVec3(1, 0, 3), shirt);
        _part('tail', v, Vector3(0, 0.38, 0.22), s);
        for (var i = 0; i < 2; i++) {
          v = {};
          VoxelModel.box(v, const IVec3(0, -4, 0), IVec3.zero, beak);
          _part('leg$i', v, Vector3((i - 0.5) * 0.12, 0.25, 0), s);
        }
    }
    // A body authored at a fixed size is shrunk into its collider, never left
    // poking out of the box the crosshair and the walls see.
    _fit = _top > height ? height / _top : 1.0;
  }
}

/// A built [Rig]: its own scene nodes over the shared [model], posed every
/// frame by [animate], placed by [place].
class RigInstance {
  RigInstance._(this.model) {
    for (final p in model.parts) {
      final pivot = Node();
      final g = p.shape.geometry;
      final mesh = Node()..scale = p.shape.shrink.clone();
      if (g != null) mesh.mesh = Mesh(g, VoxelModelMesh.material());
      pivot.add(mesh);
      root.add(pivot);
      parts[p.name] = RigPart(pivot, p.base)
        ..sx = p.sx
        ..ry = p.ry;
    }
    parts['arm0']?.rx = _armRest;
    parts['arm1']?.rx = _armRest;
    for (final p in parts.values) {
      p.apply();
    }
  }

  /// The parts and meshes it shares with every rig of its look and size.
  final RigModel model;

  /// What was built.
  Rig get rig => model.rig;

  /// The collider it was fitted to.
  double get halfWidth => model.halfWidth;

  /// The collider it was fitted to.
  double get height => model.height;

  /// The node to add to the scene; [place] moves it.
  final Node root = Node();

  /// The posable parts by name (`body`, `head`, `leg0`.., `arm0`, `arm1`,
  /// `wing0`, `wing1`, `tail`).
  final Map<String, RigPart> parts = {};

  /// What poses [parts] every frame.
  late final RigAnimator animator = RigAnimator(rig.kind, parts, armRest: _armRest, legFan: model.legFan);
  double _yaw = 0.0;
  double _age = 0.0;

  /// The yaw the model faces, eased toward what [animate] is told.
  double get yaw => _yaw;

  /// The saddle line of a quadruped (metres above the feet), 0 otherwise.
  double get backHeight => model.backHeight;

  double get _armRest => rig.armsForward ? 1.4 : 0.0;

  /// Starts an attack swing (a humanoid's arm, a bird's peck).
  void swing() => animator.startSwing();

  /// Poses the rig for one frame of [dt]: moving at [speed] metres a second,
  /// facing [targetYaw], standing [onFloor] or [flying]; [lookYaw] turns the
  /// head toward something (relative to the body), null for straight ahead.
  void animate(
    double dt, {
    required double speed,
    required double targetYaw,
    bool onFloor = true,
    bool flying = false,
    double? lookYaw,
    double verticalSpeed = 0.0,
  }) {
    _age += dt;
    _yaw = lerpAngle(_yaw, targetYaw, math.min(1.0, dt * 12.0));
    animator.pose(
      dt,
      age: _age,
      speed: speed,
      onFloor: onFloor,
      flying: flying,
      lookYaw: lookYaw,
      verticalSpeed: verticalSpeed,
    );
    for (final p in parts.values) {
      p.apply();
    }
  }

  /// Puts the model at the feet [position], [scale] times its fitted size,
  /// toppled by [topple] radians (a death) and shaken sideways by [shake].
  void place(Vector3 position, {double scale = 1.0, double topple = 0.0, double shake = 0.0}) {
    root.rotation = topple == 0.0 ? Quaternion.axisAngle(Vector3(0, 1, 0), _yaw) : eulerYXZ(topple, _yaw, 0);
    final ms = scale * model.fit;
    final sq = rig.kind == RigKind.blob ? animator.squash : 1.0;
    root.scale = Vector3(ms / math.sqrt(sq), ms * sq, ms / math.sqrt(sq));
    root.position = position + Vector3(shake, 0, 0);
  }
}
