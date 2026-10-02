import '../mobs/rig.dart';
import 'hunger_spec.dart';
import 'xp_spec.dart';

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
    this.respawnDelay = 1.0,
    this.hunger,
    this.xp,
    this.armorSlots = const ['head', 'chest', 'legs', 'feet'],
    this.armorPerPoint = 0.4,
    this.armorFloor = 0.35,
  }) : assert(armorPerPoint >= 0.0 && armorFloor >= 0.0 && armorFloor <= 1.0);

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

  /// Vertical field of view, degrees: the default of the player's
  /// `GameSettings.fov`, which the camera reads.
  final double fov;

  /// What the player starts with: item id to count.
  final Map<String, int> startingItems;

  /// Blocks break at once and placing uses nothing up; no damage.
  final bool creative;

  /// Whether falls of more than 4 blocks hurt.
  final bool fallDamage;

  /// How the player looks in third person.
  final Rig rig;

  /// Seconds after dying before the player may stand up again at the spawn
  /// (`VoxelGame.respawn`, from the death screen): a press meant for the
  /// fight does not skip it.
  final double respawnDelay;

  /// Hunger, or null for a player who never gets hungry (food then only
  /// heals and starts effects).
  final HungerSpec? hunger;

  /// Experience, or null for a player who gains none.
  final XpSpec? xp;

  /// Where armour is worn: every `Armor.slot` an item declares is one of
  /// these.
  final List<String> armorSlots;

  /// Damage each point of armour turns aside.
  final double armorPerPoint;

  /// The share of a blow that always lands, however much armour is worn.
  final double armorFloor;

  /// This player with the given fields replaced: a world's mode, say
  /// (`WorldInfo.applyTo`). A field that may be null is given as a getter of
  /// its new value, so null can be asked for, as in `VoxelGameSpec.copyWith`.
  PlayerSpec copyWith({
    double? hp,
    double? reach,
    double? meleeReach,
    double? handDamage,
    double? walkSpeed,
    double? sprintSpeed,
    double? sneakSpeed,
    double? swimSpeed,
    double? jumpVelocity,
    double? eyeHeight,
    double? halfWidth,
    double? height,
    CameraMode? camera,
    double? fov,
    Map<String, int>? startingItems,
    bool? creative,
    bool? fallDamage,
    Rig? rig,
    double? respawnDelay,
    HungerSpec? Function()? hunger,
    XpSpec? Function()? xp,
    List<String>? armorSlots,
    double? armorPerPoint,
    double? armorFloor,
  }) => PlayerSpec(
    hp: hp ?? this.hp,
    reach: reach ?? this.reach,
    meleeReach: meleeReach ?? this.meleeReach,
    handDamage: handDamage ?? this.handDamage,
    walkSpeed: walkSpeed ?? this.walkSpeed,
    sprintSpeed: sprintSpeed ?? this.sprintSpeed,
    sneakSpeed: sneakSpeed ?? this.sneakSpeed,
    swimSpeed: swimSpeed ?? this.swimSpeed,
    jumpVelocity: jumpVelocity ?? this.jumpVelocity,
    eyeHeight: eyeHeight ?? this.eyeHeight,
    halfWidth: halfWidth ?? this.halfWidth,
    height: height ?? this.height,
    camera: camera ?? this.camera,
    fov: fov ?? this.fov,
    startingItems: startingItems ?? this.startingItems,
    creative: creative ?? this.creative,
    fallDamage: fallDamage ?? this.fallDamage,
    rig: rig ?? this.rig,
    respawnDelay: respawnDelay ?? this.respawnDelay,
    hunger: hunger == null ? this.hunger : hunger(),
    xp: xp == null ? this.xp : xp(),
    armorSlots: armorSlots ?? this.armorSlots,
    armorPerPoint: armorPerPoint ?? this.armorPerPoint,
    armorFloor: armorFloor ?? this.armorFloor,
  );
}
