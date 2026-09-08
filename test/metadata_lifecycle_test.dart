import 'dart:async';
import 'dart:io';
import 'package:better_player_enhanced/better_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'mock_method_channel.dart';

class _LocalHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = MockMethodChannel();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    final initializedTextures = <int>{};
    messenger.setMockMethodCallHandler(native.channel, (call) async {
      final result = await native.handle(call);
      if (call.method == 'setDataSource') {
        final textureId = call.arguments['textureId'] as int;
        // The shared mock initializes only when the event stream is first
        // attached. Native players also initialize each replacement source.
        if (!initializedTextures.add(textureId)) {
          Timer.run(() {
            messenger.handlePlatformMessage(
              'better_player_channel/videoEvents$textureId',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'event': 'initialized',
                'height': 720.0,
                'width': 1280.0,
                'duration': 100,
              }),
              (_) {},
            );
          });
        }
      }
      return result;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(native.channel, null));

  for (final dispose in [false, true]) {
    test('late manifest cannot update a ${dispose ? 'disposed' : 'replacement'} player', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final request = Completer<HttpRequest>();
        server.listen((value) => request.complete(value));
        final controller = BetterPlayerController(const BetterPlayerConfiguration());
        try {
          await controller.setupDataSource(BetterPlayerDataSource.network(
              'http://127.0.0.1:${server.port}/old.mpd'));
          final pending = controller.pendingMetadataSetupForTesting;
          final incoming = await request.future.timeout(const Duration(seconds: 5));
          if (dispose) {
            controller.dispose(forceDispose: true);
          } else {
            await controller.setupDataSource(BetterPlayerDataSource.network(
                'https://example.test/replacement.mp4'));
          }
          incoming.response.write('''<MPD><Period><AdaptationSet>
            <Representation mimeType="video/mp4" id="stale" width="1920" height="1080"/>
            </AdaptationSet></Period></MPD>''');
          await incoming.response.close();
          await pending;
          expect(controller.betterPlayerAsmsTracks, isEmpty);
          if (!dispose) {
            expect(controller.betterPlayerDataSource!.url, 'https://example.test/replacement.mp4');
            expect(controller.betterPlayerSubtitlesSourceList, hasLength(1));
          }
        } finally {
          controller.dispose(forceDispose: true);
          await server.close(force: true);
        }
      }, _LocalHttp());
    });
  }
}
