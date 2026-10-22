import 'dart:async';

import 'package:better_player_enhanced/better_player.dart';
import 'package:better_player_enhanced/src/video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_video_player_controller.dart';

class _CountingVideoPlayerController extends MockVideoPlayerController {
  int pauseCallCount = 0;
  int disposeCallCount = 0;

  @override
  Future<void> pause() async {
    pauseCallCount += 1;
    return super.pause();
  }

  @override
  // ignore: must_call_super
  Future<void> dispose() async {
    disposeCallCount += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('better_player_channel');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('position polling stops after texture teardown error', () async {
    var positionCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'create':
          return <String, dynamic>{'textureId': 1};
        case 'play':
          return null;
        case 'position':
          positionCalls += 1;
          throw PlatformException(
            code: 'Unknown textureId',
            message: 'No video player associated with texture id 1',
          );
        default:
          return null;
      }
    });

    final controller = VideoPlayerController();
    await Future<void>.delayed(Duration.zero);

    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 750));

    expect(positionCalls, 1);
    await controller.dispose();
  });

  test('position polling does not query absolute position', () async {
    var positionCalls = 0;
    var absolutePositionCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'create':
          return <String, dynamic>{'textureId': 1};
        case 'play':
          return null;
        case 'position':
          positionCalls += 1;
          return 1000;
        case 'absolutePosition':
          absolutePositionCalls += 1;
          return 1700000000000;
        default:
          return null;
      }
    });

    final controller = VideoPlayerController();
    await Future<void>.delayed(Duration.zero);

    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 750));

    expect(positionCalls, greaterThanOrEqualTo(2));
    expect(absolutePositionCalls, 0);
    expect(controller.value.position, const Duration(seconds: 1));
    expect(controller.value.absolutePosition, isNull);

    await controller.dispose();
  });

  test('absolute position getter ignores invalid values', () async {
    var absolutePositionCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'create':
          return <String, dynamic>{'textureId': 1};
        case 'absolutePosition':
          absolutePositionCalls += 1;
          return 9223372036854775416;
        default:
          return null;
      }
    });

    final controller = VideoPlayerController();
    await Future<void>.delayed(Duration.zero);

    expect(await controller.absolutePosition, isNull);
    expect(absolutePositionCalls, 1);

    await controller.dispose();
  });

  test('position polling does not overlap a slow position call', () async {
    var positionCalls = 0;
    final slowPosition = Completer<int>();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'create':
          return <String, dynamic>{'textureId': 1};
        case 'play':
          return null;
        case 'position':
          positionCalls += 1;
          return slowPosition.future;
        default:
          return null;
      }
    });

    final controller = VideoPlayerController();
    await Future<void>.delayed(Duration.zero);

    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(positionCalls, 1);

    slowPosition.complete(2000);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(positionCalls, 2);
    expect(controller.value.position, const Duration(seconds: 2));

    await controller.dispose();
  });

  test('dispose completes when platform player creation fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'create') {
        throw PlatformException(
          code: 'create_failed',
          message: 'Failed to create platform player',
        );
      }
      return null;
    });

    final controller = VideoPlayerController();
    await expectLater(
      controller.dispose().timeout(const Duration(seconds: 1)),
      completes,
    );
  });

  test('better player dispose does not send an extra pause command', () {
    final controller = BetterPlayerController(
      const BetterPlayerConfiguration(),
    );
    final videoController = _CountingVideoPlayerController();
    controller.videoPlayerController = videoController;

    controller.dispose();

    expect(videoController.pauseCallCount, 0);
    expect(videoController.disposeCallCount, 1);
  });
}
