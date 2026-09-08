import 'package:better_player_enhanced/src/asms/better_player_asms_audio_track.dart';
import 'package:better_player_enhanced/src/asms/better_player_asms_data_holder.dart';
import 'package:better_player_enhanced/src/asms/better_player_asms_subtitle.dart';
import 'package:better_player_enhanced/src/asms/better_player_asms_track.dart';
import 'package:better_player_enhanced/src/core/better_player_utils.dart';
import 'package:better_player_enhanced/src/hls/hls_parser/mime_types.dart';
import 'package:xml/xml.dart';
import 'package:flutter/foundation.dart';

enum _MediaType { audio, video, text }

///DASH helper class
class BetterPlayerDashUtils {
  static Future<BetterPlayerAsmsDataHolder> parse(
      String data, String masterPlaylistUrl) {
    // async alone does not move XML/entity decoding off the UI isolate.
    // Only transfer input strings and extracted metadata, never the XML tree.
    return compute(_parseManifest, (data, masterPlaylistUrl),
        debugLabel: 'BetterPlayer DASH metadata');
  }

  static BetterPlayerAsmsDataHolder _parseManifest((String, String) input) {
    final (data, masterPlaylistUrl) = input;
    List<BetterPlayerAsmsTrack> tracks = [];
    final List<BetterPlayerAsmsAudioTrack> audios = [];
    final List<BetterPlayerAsmsSubtitle> subtitles = [];
    try {
      int audiosCount = 0;
      final document = XmlDocument.parse(data);
      final adaptationSets = document.findAllElements('AdaptationSet');
      adaptationSets.forEach((adaptationNode) {
        adaptationNode.findAllElements('Representation').forEach(
          (node) {
            final mimeType = node.getAttribute('mimeType');
            final contentType = node.getAttribute('contentType');
            final codecs = node.getAttribute('codecs');

            final mediaType = _getMediaType(
              mimeType: mimeType,
              contentType: contentType,
              codecs: codecs,
            );

            switch (mediaType) {
              case _MediaType.audio:
                audios.add(parseAudio(node, audiosCount));
                audiosCount += 1;
                break;
              case _MediaType.video:
                tracks.add(parseVideo(node));
                break;
              case _MediaType.text:
                subtitles.add(parseSubtitle(masterPlaylistUrl, node));
                break;
              default:
                break;
            }
          },
        );
      });
    } catch (exception) {
      BetterPlayerUtils.log("Exception on dash parse: $exception");
    }
    return BetterPlayerAsmsDataHolder(
        tracks: tracks, audios: audios, subtitles: subtitles);
  }

  static _MediaType? _getMediaType({
    String? mimeType,
    String? contentType,
    String? codecs,
  }) {
    if (mimeType != null) {
      // first check mimeType to identify if it is audio, video or text
      if (MimeTypes.isVideo(mimeType)) {
        return _MediaType.video;
      }
      if (MimeTypes.isAudio(mimeType)) {
        return _MediaType.audio;
      }
      if (MimeTypes.isText(mimeType)) {
        return _MediaType.text;
      }
    }

    if (contentType != null) {
      // if mimeType is not present some MPDs content type can be present
      if (contentType == "video") {
        return _MediaType.video;
      }
      if (contentType == "audio") {
        return _MediaType.audio;
      }
      if (contentType == "text") {
        return _MediaType.text;
      }
    }

    if (codecs != null) {
      // if there is neither mimeType nor contentType then check codecs
      if (codecs.startsWith('avc1') ||
          codecs.startsWith('hev1') ||
          codecs.startsWith('vp9') ||
          codecs.startsWith('av01')) {
        return _MediaType.video;
      }
      if (codecs.startsWith('mp4a') ||
          codecs.startsWith('opus') ||
          codecs.startsWith('ac-3') ||
          codecs.startsWith('ec-3')) {
        return _MediaType.audio;
      }
      if (codecs.contains('stpp') || codecs.contains('wvtt')) {
        return _MediaType.text;
      }
    }
    return null;
  }

  static BetterPlayerAsmsTrack parseVideo(XmlElement representationNode) {
    final String? id = representationNode.getAttribute('id');
    final int width =
        int.parse(representationNode.getAttribute('width') ?? '0');
    final int height =
        int.parse(representationNode.getAttribute('height') ?? '0');
    final int bitrate =
        int.parse(representationNode.getAttribute('bandwidth') ?? '0');
    final int frameRate =
        int.parse(representationNode.getAttribute('frameRate') ?? '0');
    final String? codecs = representationNode.getAttribute('codecs');
    final String? mimeType = MimeTypes.getMediaMimeType(codecs ?? '');

    return BetterPlayerAsmsTrack(
        id, width, height, bitrate, frameRate, codecs, mimeType);
  }

  static BetterPlayerAsmsAudioTrack parseAudio(XmlElement node, int index) {
    final String segmentAlignmentStr =
        node.getAttribute('segmentAlignment') ?? '';
    String? label = node.getAttribute('label');
    final String? language = node.getAttribute('lang');
    final String? mimeType = node.getAttribute('mimeType');

    label ??= language;

    return BetterPlayerAsmsAudioTrack(
        id: index,
        segmentAlignment: segmentAlignmentStr.toLowerCase() == 'true',
        label: label,
        language: language,
        mimeType: mimeType);
  }

  static BetterPlayerAsmsSubtitle parseSubtitle(
      String masterPlaylistUrl, XmlElement node) {
    final String segmentAlignmentStr =
        node.getAttribute('segmentAlignment') ?? '';
    String? name = node.getAttribute('label');
    final String? language = node.getAttribute('lang');
    final String? mimeType = node.getAttribute('mimeType');
    String? url =
        node.getElement('Representation')?.getElement('BaseURL')?.value;
    if (url?.contains("http") == false) {
      final Uri masterPlaylistUri = Uri.parse(masterPlaylistUrl);
      final pathSegments = <String>[...masterPlaylistUri.pathSegments];
      pathSegments[pathSegments.length - 1] = url!;
      url = Uri(
              scheme: masterPlaylistUri.scheme,
              host: masterPlaylistUri.host,
              port: masterPlaylistUri.port,
              pathSegments: pathSegments)
          .toString();
    }

    if (url != null && url.startsWith('//')) {
      url = 'https:$url';
    }

    name ??= language;

    return BetterPlayerAsmsSubtitle(
        name: name,
        language: language,
        mimeType: mimeType,
        segmentAlignment: segmentAlignmentStr.toLowerCase() == 'true',
        url: url,
        realUrls: [url ?? '']);
  }
}
