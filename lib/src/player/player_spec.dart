import '../mobs/rig.dart';

/// First person or behind the shoulder.
enum CameraMode {
  /// The eye is the player's.
  firstPerson,

  /// The camera orbits behind, pulled in by walls.
  thirdPerson,
}

/// The player, declared.
class PlayerSpec {
  /// A player; the defaults are a block sandbox's usual feel.
  const PlayerSpec({
    this.hp = 20.0,
    this.reach = 5.0,
    this.meleeReach = 3.6,
    this.handDamage = 1.0,
    this.walkSpeed = 4.6,
    this.sprintSpeed = 7.6,
    this.sneakSpeed = 2.0,
    this.swimSpeed = 3.0,
    this.jumpVelocity = 8.6,
    this.eyeHeight = 1.62,
    this.halfWidth = 0.3,
    this.height = 1.75,
    this.camera = CameraMode.firstPerson,
    this.fov = 72.0,
    this.startingItems = const {},
    this.creative = false,
    this.fallDamage = true,
    this.rig = const Rig.humanoid(),
    this.respawnSeconds = 3.0,
  });

  /// Health.
  final double hp;

  /// How far blocks are mined and placed.
  final double reach;

  /// How far a creature is hit.
  final double meleeReach;

  /// Damage of a bare-handed (or tool-less) hit.
  final double handDamage;

  /// Walking speed, metres a second.
  final double walkSpeed;

  /// Running speed.
  final double sprintSpeed;

  /// Sneaking speed.
  final double sneakSpeed;

  /// Swimming speed.
  final double swimSpeed;

  /// Jump launch speed.
  final double jumpVelocity;

  /// The eye above the feet.
  final double eyeHeight;

  /// Half the collider's width.
  final double halfWidth;

  /// The collider's height.
  final double height;

  /// The starting view.
  final CameraMode camera;

  /// Vertical field of view, degrees.
  final double fov;

  /// What the player starts with: item id to count.
  final Map<String, int> startingItems;

  /// Blocks break at once and placing uses nothing up; no damage.
  final bool creative;

  /// Whether falls of more than 4 blocks hurt.
  final bool fallDamage;

  /// How the player looks in third person.
  final Rig rig;

  /// Seconds between dying and standing again at the spawn.
  final double respawnSeconds;
}
