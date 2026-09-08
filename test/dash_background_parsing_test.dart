import 'dart:async';

import 'package:better_player_enhanced/src/dash/better_player_dash_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'background parsing preserves video and ordered audio metadata',
    () async {
      final result = await BetterPlayerDashUtils.parse('''
      <MPD><Period><AdaptationSet>
        <Representation id="video" mimeType="video/mp4" codecs="avc1.640028"
          width="1920" height="1080" bandwidth="4000000" frameRate="30"/>
        <Representation mimeType="audio/mp4" label="English &amp; original" lang="en" segmentAlignment="true"/>
        <Representation mimeType="audio/mp4" lang="fr"/>
        <Representation mimeType="text/vtt" lang="en">
          <Representation><BaseURL>captions.vtt</BaseURL></Representation>
        </Representation>
      </AdaptationSet></Period></MPD>
    ''', 'https://example.test/media/manifest.mpd');
      expect(result.tracks!.single.id, 'video');
      expect(result.tracks!.single.width, 1920);
      expect(result.tracks!.single.bitrate, 4000000);
      expect(result.audios!.map((a) => a.id), [0, 1]);
      expect(result.audios!.map((a) => a.label), ['English & original', 'fr']);
      expect(result.audios!.first.segmentAlignment, isTrue);
      expect(result.subtitles!.single.language, 'en');
      expect(result.subtitles!.single.mimeType, 'text/vtt');
    },
  );

  test('malformed XML retains empty-result error behavior', () async {
    final result = await BetterPlayerDashUtils.parse(
      '<MPD>',
      'https://example.test/a.mpd',
    );
    expect(result.tracks, isEmpty);
    expect(result.audios, isEmpty);
    expect(result.subtitles, isEmpty);
  });

  test(
    'entity-heavy parsing leaves the caller event loop responsive',
    () async {
      final text = List.filled(100000, '&amp;').join();
      final uiTurn = Completer<String>();
      Timer.run(() => uiTurn.complete('event-loop'));
      final parsing = BetterPlayerDashUtils.parse(
        '<MPD><Period><Label>$text</Label></Period></MPD>',
        'https://example.test/a.mpd',
      );
      expect(
        await Future.any([uiTurn.future, parsing.then((_) => 'parse')]),
        'event-loop',
      );
      await parsing;
    },
  );
}
