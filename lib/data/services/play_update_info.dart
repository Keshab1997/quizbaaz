/// Play in-app update availability, normalised so the Android io backend and
/// the web/stub backend can share one shape (the conditional import picks
/// exactly one of them).
class PlayUpdateInfo {
  const PlayUpdateInfo({
    required this.updateAvailable,
    required this.flexibleAllowed,
    required this.availableVersionCode,
  });

  /// No newer bundle known — the default everywhere Play is absent.
  const PlayUpdateInfo.none()
    : updateAvailable = false,
      flexibleAllowed = false,
      availableVersionCode = 0;

  final bool updateAvailable;

  /// Whether Play allows the *flexible* (background-download) flow. The app
  /// only ever offers that one; the immediate flow restarts the app without
  /// asking, which is exactly what must never happen mid-session.
  final bool flexibleAllowed;

  /// Version code of the pending bundle; 0 when nothing is available.
  final int availableVersionCode;
}
