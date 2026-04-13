import 'dart:convert';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _mapAsset = 'map.json';

void main() {
  runApp(const MaterialApp(home: GameScreen()));
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<Vector2> _spawn = _loadInitialPoint();

  Future<Vector2> _loadInitialPoint() async {
    final raw = await rootBundle.loadString('assets/images/$_mapAsset');
    final data = json.decode(raw) as Map<String, dynamic>;
    for (final layer in (data['layers'] as List)) {
      if (layer['type'] != 'objectgroup') continue;
      for (final obj in (layer['objects'] as List? ?? const [])) {
        if (obj['name'] == 'initialPoint') {
          return Vector2(
            (obj['x'] as num).toDouble(),
            (obj['y'] as num).toDouble(),
          );
        }
      }
    }
    return Vector2.zero();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Vector2>(
        future: _spawn,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return BonfireWidget(
            cameraConfig: CameraConfig(zoom: 1),
            showCollisionArea: true,
            player: PawnPlayer(snap.data!),
            map: WorldMapByTiled(WorldMapReader.fromAsset(_mapAsset)),
            playerControllers: [
              Joystick(
                directional: JoystickDirectional(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PawnPlayer extends SimplePlayer {
  PawnPlayer(Vector2 position)
      : super(
          position: position,
          size: Vector2.all(128),
          speed: 80,
          animation: SimpleDirectionAnimation(
            idleRight: SpriteAnimation.load(
              'TinySwords/Units/Blue Units/Pawn/Pawn_Idle.png',
              SpriteAnimationData.sequenced(
                amount: 8,
                stepTime: 0.1,
                textureSize: Vector2.all(192),
              ),
            ),
            runRight: SpriteAnimation.load(
              'TinySwords/Units/Blue Units/Pawn/Pawn_Run.png',
              SpriteAnimationData.sequenced(
                amount: 6,
                stepTime: 0.1,
                textureSize: Vector2.all(192),
              ),
            ),
          ),
        );
}
