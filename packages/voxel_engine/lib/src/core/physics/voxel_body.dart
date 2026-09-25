import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../grid/block_collision.dart';
import '../grid/block_shape.dart';
import '../grid/voxel_block_table.dart';
import '../math/ivec3.dart';

/// What a body or a ray needs to read from a world: the block at a cell and
/// what that block is.
abstract interface class VoxelQuery {
  /// What each block id is.
  VoxelBlockTable get table;

  /// The block id at a world cell; air where nothing is generated.
  int getBlockXYZ(int x, int y, int z);
}

/// An AABB anchored at the feet, swept against the block volume one axis at a
/// time. Knows nothing of rendering: a game moves its visuals from [position].
class VoxelBody {
  /// The gap a body keeps from what it touches, so a resting body does not
  /// count as overlapping the floor.
  static const double skin = 0.001;

  /// Downward acceleration in air, cells per second squared.
  double gravity = 26.0;

  /// Downward acceleration in a liquid; the sink speed there is capped at 3.
  double liquidGravity = 4.0;

  /// The middle of the body's feet, in world cells.
  Vector3 position = Vector3.zero();

  /// Half the box's width on x and on z.
  double halfWidth = 0.3;

  /// The box's height above [position].
  double height = 1.75;

  /// Cells per second, applied by [move].
  Vector3 velocity = Vector3.zero();

  /// The last [move] ended standing on something.
  bool onFloor = false;

  /// In any liquid, at the feet or the head.
  bool inLiquid = false;

  /// The head cell holds a liquid.
  bool headInLiquid = false;

  /// Standing on the floor with the head in the open: the body wades through a
  /// shallow liquid instead of swimming in it. A one-block puddle is walked;
  /// only water deep enough to cover the head is swum.
  bool get wading => inLiquid && onFloor && !headInLiquid;

  /// The liquid kind at the feet cell, or [VoxelBlockDef.noLiquid].
  int feetLiquid = VoxelBlockDef.noLiquid;

  /// The liquid kind at the head cell, or [VoxelBlockDef.noLiquid].
  int headLiquid = VoxelBlockDef.noLiquid;

  /// The last [move] was stopped on x or z.
  bool hitWall = false;

  /// The world the body moves in; set by [setup].
  late VoxelQuery query;

  /// A ghost passes through every block.
  bool noclip = false;

  /// Fences stand [fenceBarrierHeight] tall to this body, above its jump: an
  /// animal stays in its pen. Off, a fence is the one block it is drawn as.
  bool fenceBarrier = false;

  /// The horizontal direction the last move was stopped in.
  Vector3 _blocked = Vector3.zero();

  /// Places the body in world [q] with half width [hw] and height [h]. Call
  /// before the first [move].
  void setup(VoxelQuery q, double hw, double h) {
    query = q;
    halfWidth = hw;
    height = h;
  }

  /// The middle of the box.
  Vector3 centre() => position + Vector3(0, height * 0.5, 0);

  /// The ray parameter at which the ray enters the body's box grown by
  /// [inflate] on every side: 0 when [origin] is inside, -1 when it misses.
  double rayDistance(Vector3 origin, Vector3 direction, [double inflate = 0.0]) {
    final mn = position - Vector3(halfWidth + inflate, inflate, halfWidth + inflate);
    final mx = position + Vector3(halfWidth + inflate, height + inflate, halfWidth + inflate);
    var near = double.negativeInfinity;
    var far = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final d = direction[axis];
      final inv = d != 0.0 ? 1.0 / d : double.infinity;
      final a = (mn[axis] - origin[axis]) * inv;
      final b = (mx[axis] - origin[axis]) * inv;
      final lo = a < b ? a : b;
      final hi = a > b ? a : b;
      if (lo > near) near = lo;
      if (hi < far) far = hi;
    }
    if (far < near || far < 0.0) return -1.0;
    return near > 0.0 ? near : 0.0;
  }

  /// Accelerates [velocity] down for [dt] seconds: [gravity] in air and while
  /// [wading], [liquidGravity] in a liquid deep enough to swim in, with the
  /// sink speed capped at 3.
  ///
  /// A wading body falls at the air rate on purpose. At the liquid rate one
  /// tick of falling moves it less than [skin], so the sweep does not reach
  /// the floor every other tick and `onFloor` flickers — which the animation
  /// then wears.
  void applyGravity(double dt) {
    if (inLiquid && !wading) {
      velocity.y = (velocity.y - liquidGravity * dt).clamp(-3.0, double.infinity);
    } else {
      velocity.y -= gravity * dt;
    }
  }

  /// Moves by [velocity] for [dt] seconds, x then z then y, stopping flush
  /// against every collision box. Updates [onFloor], [hitWall] and the liquid
  /// senses; a blocked axis loses its velocity. [noclip] skips the collisions.
  void move(double dt) {
    final next = position.clone();
    hitWall = false;
    _blocked = Vector3.zero();
    if (noclip) {
      position = next + velocity * dt;
      onFloor = false;
      _senseFluids();
      return;
    }
    // A box the body already stands in (a ladder placed on it, a fence arm
    // that grew into it) lets it out instead of snapping it through. On y only
    // a box beside the body does: one it is sunk into still lifts it out.
    final from = position.clone();
    next.x += velocity.x * dt;
    var hit = _solidBoxesAt(next, escape: from);
    if (hit.isNotEmpty) {
      next.x = _resolveAxis(hit, 0, velocity.x > 0.0);
      _blocked.x = velocity.x > 0.0 ? 1.0 : -1.0;
      velocity.x = 0.0;
      hitWall = true;
    }
    next.z += velocity.z * dt;
    hit = _solidBoxesAt(next, escape: from);
    if (hit.isNotEmpty) {
      next.z = _resolveAxis(hit, 2, velocity.z > 0.0);
      _blocked.z = velocity.z > 0.0 ? 1.0 : -1.0;
      velocity.z = 0.0;
      hitWall = true;
    }
    onFloor = false;
    next.y += velocity.y * dt;
    hit = _solidBoxesAt(next, escape: from, vertical: true);
    if (hit.isNotEmpty) {
      if (velocity.y > 0.0) {
        next.y = _resolveAxis(hit, 1, true);
      } else {
        next.y = _resolveAxis(hit, 1, false);
        onFloor = true;
      }
      velocity.y = 0.0;
    }
    position = next;
    _senseFluids();
  }

  /// The coordinate along [axis] that puts the body flush against the boxes it
  /// just entered: moving positive, the nearest box face on the near side;
  /// moving negative, the farthest far face. The sweep is one axis at a time,
  /// so every box in [hit] was entered along this axis.
  double _resolveAxis(List<CollisionBox> hit, int axis, bool positive) {
    final extent = axis == 1 ? height : halfWidth;
    if (positive) {
      var face = double.infinity;
      for (final box in hit) {
        face = math.min(face, box.min(axis));
      }
      return face - extent - skin;
    }
    var face = double.negativeInfinity;
    for (final box in hit) {
      face = math.max(face, box.max(axis));
    }
    return face + skin + (axis == 1 ? 0.0 : extent);
  }

  void _senseFluids() {
    final feetId = query.getBlockXYZ(position.x.floor(), (position.y + 0.3).floor(), position.z.floor());
    final headId = query.getBlockXYZ(position.x.floor(), (position.y + height - 0.15).floor(), position.z.floor());
    final t = query.table;
    feetLiquid = t.liquidKind(feetId);
    headLiquid = t.liquidKind(headId);
    headInLiquid = t.isLiquid(headId);
    // The feet probe rides 0.3 above the soles, so a body that bobs at the
    // surface — or walks through a one-block puddle — crosses it many times a
    // second, and everything the liquid gates (gravity, speed, the splash, the
    // pose) chatters with it. Entering is still decided at the probe; leaving
    // is decided at the soles, 0.3 lower, and that gap is the hysteresis.
    final soleId = query.getBlockXYZ(position.x.floor(), (position.y + 0.02).floor(), position.z.floor());
    final wet = t.isLiquid(feetId) || headInLiquid;
    inLiquid = inLiquid ? (wet || t.isLiquid(soleId)) : wet;
  }

  /// A step high enough to stand on a slab or the low step of stairs.
  static const double halfStep = 0.52;

  /// A step high enough to stand on a whole block.
  static const double fullStep = 1.02;

  /// The step the body just walked into — [halfStep], [fullStep] or 0 when
  /// there is none to climb. Nothing is ever lifted into place: a body that
  /// meets a step jumps it, which is what this answers for. The body is also
  /// tested a hair further in the blocked direction, so a half step never wins
  /// against a full-height wall.
  double stepAhead({bool fullBlock = true}) {
    if (!hitWall || !onFloor) return 0.0;
    if (stepFits(halfStep)) return halfStep;
    if (fullBlock && stepFits(fullStep)) return fullStep;
    return 0.0;
  }

  /// Would the body, lifted by [lift] and nudged a hair toward the wall it just
  /// hit, stand clear of every block? [stepAhead] asks it of each step height;
  /// a swimmer climbing a bank asks it of every lift that would clear the lip.
  bool stepFits(double lift) {
    final up = position + Vector3(0, lift, 0);
    return !_overlapsSolid(up) && !_overlapsSolid(up + _blocked * 0.05);
  }

  /// Cube-based on purpose: callers ask "is the body in this CELL" (a block
  /// about to be placed, a door), which does not depend on the block's shape.
  bool overlapsBlock(IVec3 b) =>
      b.x < position.x + halfWidth &&
      b.x + 1.0 > position.x - halfWidth &&
      b.y < position.y + height &&
      b.y + 1.0 > position.y &&
      b.z < position.z + halfWidth &&
      b.z + 1.0 > position.z - halfWidth;

  bool _overlapsSolid(Vector3 at) => _solidBoxesAt(at, firstOnly: true).isNotEmpty;

  /// Every collision box (world space) that overlaps the body placed at [at],
  /// shrunk by [skin]. The row below the feet is scanned too: a fence barrier
  /// is 1.5 tall and reaches into the cell above its own. [firstOnly] stops at
  /// the first hit (a yes/no query). A box the body also overlaps at [escape]
  /// is left out; for a [vertical] move, only when it is [_beside] the body.
  List<CollisionBox> _solidBoxesAt(Vector3 at, {bool firstOnly = false, Vector3? escape, bool vertical = false}) {
    final out = <CollisionBox>[];
    final bx0 = at.x - halfWidth + skin;
    final bx1 = at.x + halfWidth - skin;
    final by0 = at.y + skin;
    final by1 = at.y + height - skin;
    final bz0 = at.z - halfWidth + skin;
    final bz1 = at.z + halfWidth - skin;
    final minX = bx0.floor();
    final maxX = bx1.floor();
    final minY = by0.floor() - 1;
    final maxY = by1.floor();
    final minZ = bz0.floor();
    final maxZ = bz1.floor();
    for (var y = minY; y <= maxY; y++) {
      for (var z = minZ; z <= maxZ; z++) {
        for (var x = minX; x <= maxX; x++) {
          // y < 0 is solid rock.
          final boxes = y < 0
              ? const [CollisionBox.full]
              : collisionBoxesAt(query, x, y, z, fenceBarrier: fenceBarrier);
          for (final box in boxes) {
            final p = box.shifted(x, y, z);
            if (p.x0 < bx1 && p.x1 > bx0 && p.y0 < by1 && p.y1 > by0 && p.z0 < bz1 && p.z1 > bz0) {
              if (escape != null && _overlaps(p, escape) && (!vertical || _beside(p, escape))) continue;
              out.add(p);
              if (firstOnly) return out;
            }
          }
        }
      }
    }
    return out;
  }

  /// Whether the body placed at [at], shrunk by [skin], overlaps [p].
  bool _overlaps(CollisionBox p, Vector3 at) =>
      p.x0 < at.x + halfWidth - skin &&
      p.x1 > at.x - halfWidth + skin &&
      p.y0 < at.y + height - skin &&
      p.y1 > at.y + skin &&
      p.z0 < at.z + halfWidth - skin &&
      p.z1 > at.z - halfWidth + skin;

  /// Whether the body placed at [at] reaches into [p] less from a side than
  /// from above or below: a ladder beside it, not a floor it is sunk into.
  bool _beside(CollisionBox p, Vector3 at) {
    final side = math.min(
      math.min(p.x1 - (at.x - halfWidth), at.x + halfWidth - p.x0),
      math.min(p.z1 - (at.z - halfWidth), at.z + halfWidth - p.z0),
    );
    final vertical = math.min(p.y1 - at.y, at.y + height - p.y0);
    return side < vertical;
  }

  /// Is there a solid block directly in front (for climbing)? Cube-based on
  /// purpose: climbing reads the cell, the shape inside it does not matter.
  /// The lowest probe is the feet cell itself: a probe above the feet loses the
  /// wall while the feet are still below its top, and a climber stalls there,
  /// falling back and climbing again, instead of reaching the top.
  bool wallAhead(Vector3 direction) {
    final probe = position + direction.normalized() * (halfWidth + 0.35);
    for (final dy in [0.0, 1.0, height - 0.2]) {
      if (_solidCell(probe.x.floor(), (position.y + dy).floor(), probe.z.floor())) return true;
    }
    return false;
  }

  /// y < 0 is solid rock.
  bool _solidCell(int x, int y, int z) => y < 0 || query.table.isSolid(query.getBlockXYZ(x, y, z));
}
