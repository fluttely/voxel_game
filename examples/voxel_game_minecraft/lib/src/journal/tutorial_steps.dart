import 'package:voxel_game/voxel_game.dart';

import 'tutorial.dart';
import 'tutorial_step.dart';

/// The tutorial's ten first steps, in order.
const List<TutorialStep> tutorialSteps = [
  TutorialStep('move', 'Walk', 'Press W A S D to walk around.', when: _walked),
  TutorialStep('look', 'Look', 'Move the mouse to look around.', when: _looked),
  TutorialStep('jump', 'Jump', 'Press Space to jump. Walk into a one-block step to hop up.', when: _jumped),
  TutorialStep('break', 'Break a block', 'Hold the left mouse button on a block until it breaks.', on: _broke),
  TutorialStep('inventory', 'Open your bag', 'Press E to open your bag and the things you can make.', on: _bagged),
  TutorialStep(
    'craft',
    'Make a tool',
    'Logs make planks, planks make sticks, planks and sticks make a pickaxe. Click a recipe.',
    on: _madeTool,
  ),
  TutorialStep(
    'place',
    'Place a block',
    'Pick a block on the hotbar (1-9) and press the right mouse button.',
    on: _placed,
  ),
  TutorialStep('eat', 'Eat', 'Hold food and press the right mouse button when the hunger bar drops.', on: _ate),
  TutorialStep(
    'sleep',
    'Sleep',
    'Make a bed (3 planks and 3 wool) and use it at night, or stay alive until the sun comes up.',
    on: _slept,
    when: _sunRose,
  ),
  TutorialStep(
    'journal',
    'Read the journal',
    'Press J: talents, creatures, achievements and quests.',
    on: _readJournal,
  ),
];

/// Metres walked that finish the first step.
const double walkToFinish = 2.0;

/// How far the view turns (radians, yaw and pitch told together) to finish
/// the second.
const double lookToFinish = 0.5;

bool _walked(VoxelGame game, Tutorial t) => t.walked >= walkToFinish;

bool _looked(VoxelGame game, Tutorial t) => t.turned >= lookToFinish;

bool _jumped(VoxelGame game, Tutorial t) => game.input.justPressed(VoxelAction.jump);

bool _broke(VoxelGame game, GameEvent e) => e is BlockBroken;

bool _bagged(VoxelGame game, GameEvent e) => e is ScreenOpened && e.screen is BagScreen;

bool _madeTool(VoxelGame game, GameEvent e) => e is ItemCrafted && game.items[e.recipe.result].tool != null;

bool _placed(VoxelGame game, GameEvent e) => e is BlockPlaced;

bool _ate(VoxelGame game, GameEvent e) => e is FoodEaten;

bool _slept(VoxelGame game, GameEvent e) => e is Slept;

bool _sunRose(VoxelGame game, Tutorial t) => t.sunRose;

bool _readJournal(VoxelGame game, GameEvent e) => e is ScreenOpened && e.screen == const DeclaredScreen('journal');
