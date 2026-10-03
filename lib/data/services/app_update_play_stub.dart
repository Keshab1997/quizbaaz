import 'play_update_info.dart';

/// Web / desktop / widget-test fallback: no Play Store exists, so the update
/// check always answers "nothing available" and the download entry points
/// fail soft with a line the UI can show.
Future<PlayUpdateInfo> checkPlayUpdate() async => const PlayUpdateInfo.none();

Future<String?> startFlexiblePlayUpdate() async =>
    'Play in-app update is not available on this platform';

Future<String?> completePlayUpdate() async =>
    'Play in-app update is not available on this platform';
