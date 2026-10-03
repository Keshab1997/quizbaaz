/// What the dashboard's update banner should offer right now.
enum UpdateBannerTarget {
  /// Nothing to say — the banner stays hidden.
  none,

  /// First launch after an install/update: offer this build's "What's new"
  /// notes (tap opens the Update Center, never a modal out of nowhere).
  whatsNew,

  /// Play reports a newer bundle the player has not dismissed yet.
  availableUpdate,
}
