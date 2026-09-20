import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/providers/battle_provider.dart';
import '../../../data/services/online_presence_service.dart';
import '../../../data/services/challenge_service.dart';
import '../../../data/providers/user_provider.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/cached_avatar.dart';
import 'battle_screen.dart';

/// Screen showing online users available for 1v1 battle challenge.
///
/// Features:
/// - Real-time list of online users (Firestore stream)
/// - Tap any user to send a challenge
/// - Shows incoming challenge notifications
/// - Battle difficulty selector
/// - Animated "searching..." and VS transitions
class OnlineBattleScreen extends StatefulWidget {
  const OnlineBattleScreen({super.key});

  @override
  State<OnlineBattleScreen> createState() => _OnlineBattleScreenState();
}

class _OnlineBattleScreenState extends State<OnlineBattleScreen>
    with WidgetsBindingObserver {
  final OnlinePresenceService _presence = OnlinePresenceService();
  final ChallengeService _challengeService = ChallengeService();

  List<OnlineUser> _onlineUsers = [];
  bool _isLoading = true;
  String? _pendingChallengeToUid;
  StreamSubscription? _presenceSub;
  StreamSubscription? _incomingChallengeSub;
  StreamSubscription? _outgoingChallengeSub;
  Timer? _heartbeatTimer;

  String _selectedDifficulty = 'normal';
  ChallengeData? _incomingChallenge;
  ChallengeData? _outgoingChallenge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePresence();
    _startHeartbeat();
    _watchOnlineUsers();
    _watchIncomingChallenges();
  }

  Future<void> _initializePresence() async {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;

    await _presence.goOnline(
      uid: user.userId,
      name: user.username,
      avatar: user.avatarPath,
      avatarUrl: user.avatarUrl,
      level: user.level,
      isAvailable: true,
      activity: 'idle',
    );

    _presence.cleanupStaleEntries();
    // Only this player's own stale challenges — a collection-wide cleanup is
    // not something the participant-only rules allow (R17).
    _challengeService.expireMyChallenges(user.userId);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      OnlinePresenceService.heartbeatInterval,
      (_) {
        _presence.heartbeat(
          isAvailable: _pendingChallengeToUid == null &&
              _incomingChallenge == null,
          activity: 'idle',
        );
      },
    );
  }

  void _watchOnlineUsers() {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    _presenceSub = _presence
        .watchOnlineUsers(excludeUid: userProvider.user.userId)
        .listen((users) {
      if (!mounted) return;
      setState(() {
        _onlineUsers = users;
        _isLoading = false;
      });
    });
  }

  void _watchIncomingChallenges() {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    _incomingChallengeSub = _challengeService
        .watchIncomingChallenges(userProvider.user.userId)
        .listen((challenge) {
      if (challenge != null && challenge.isPending && !challenge.hasExpired) {
        setState(() => _incomingChallenge = challenge);
        if (mounted) {
          _showIncomingChallengeDialog(challenge);
        }
      }
    });
  }

  void _watchOutgoingChallenge() {
    _outgoingChallengeSub?.cancel();
    if (!mounted) return;
    final myUid = context.read<UserProvider>().user.userId;
    _outgoingChallengeSub = _challengeService
        .watchOutgoingChallenge(myUid)
        .listen((challenge) {
      if (challenge == null) {
        if (!mounted) return;
        setState(() {
          _pendingChallengeToUid = null;
          _outgoingChallenge = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() => _outgoingChallenge = challenge);

      if (challenge.isAccepted) {
        _startBattleWithOpponent(
          challengeId: challenge.challengeId,
          opponentUid: challenge.toUid,
          opponentName: challenge.toName,
          opponentAvatar: challenge.toAvatar,
          opponentAvatarUrl: challenge.toAvatarUrl,
          difficulty: challenge.difficulty,
        );
      } else if (challenge.isRejected ||
          challenge.isExpired ||
          challenge.isCancelled) {
        setState(() {
          _pendingChallengeToUid = null;
          _outgoingChallenge = null;
        });
        if (mounted) {
          _showChallengeResultSnackbar(
            challenge.toName,
            challenge.status,
          );
        }
      }
    });
  }

  Future<void> _sendChallenge(OnlineUser user) async {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    final myUser = userProvider.user;

    if (myUser.isGuest) {
      if (!mounted) return;
      _showGuestRestrictionDialog();
      return;
    }

    final isOnline = await _presence.isUserOnline(user.uid);
    if (!isOnline) {
      if (!mounted) return;
      _showSnackBar('${user.name} is no longer online');
      return;
    }

    if (!mounted) return;
    setState(() => _pendingChallengeToUid = user.uid);

    final challengeId = await _challengeService.sendChallenge(
      fromUid: myUser.userId,
      fromName: myUser.username,
      fromAvatar: myUser.avatarPath,
      fromAvatarUrl: myUser.avatarUrl,
      fromLevel: myUser.level,
      targetUid: user.uid,
      targetName: user.name,
      targetAvatar: user.avatar,
      targetAvatarUrl: user.avatarUrl,
      difficulty: _selectedDifficulty,
    );

    if (challengeId != null) {
      _watchOutgoingChallenge();
      if (mounted) {
        _showChallengeSentDialog(user);
      }
    } else {
      if (!mounted) return;
      setState(() => _pendingChallengeToUid = null);
      _showSnackBar('Could not send challenge. Try again!');
    }
  }

  Future<void> _acceptChallenge(ChallengeData challenge) async {
    final success =
        await _challengeService.acceptChallenge(challenge.challengeId);
    if (!success) {
      if (mounted) _showSnackBar('Could not accept the challenge. Try again!');
      return;
    }
    if (mounted) Navigator.of(context).pop();
    await _startBattleWithOpponent(
      challengeId: challenge.challengeId,
      opponentUid: challenge.fromUid,
      opponentName: challenge.fromName,
      opponentAvatar: challenge.fromAvatar,
      opponentAvatarUrl: challenge.fromAvatarUrl,
      difficulty: challenge.difficulty,
    );
  }

  Future<void> _rejectChallenge(ChallengeData challenge) async {
    await _challengeService.rejectChallenge(challenge.challengeId);
    if (mounted) Navigator.of(context).pop();
    if (!mounted) return;
    setState(() => _incomingChallenge = null);
  }

  Future<void> _cancelOutgoingChallenge() async {
    if (_outgoingChallenge != null) {
      await _challengeService.cancelChallenge(_outgoingChallenge!.challengeId);
    }
    if (!mounted) return;
    setState(() {
      _pendingChallengeToUid = null;
      _outgoingChallenge = null;
    });
    Navigator.of(context).pop();
  }

  /// Starts the battle the challenge was about (R10).
  ///
  /// The opponent is *known* here — this is the exact player who accepted —
  /// so the match is started through
  /// [BattleProvider.startBattleWithOpponent], which creates/joins the
  /// deterministic room for the two uids and never substitutes a random or
  /// bot opponent. Only after the provider reports a real match does the
  /// screen navigate — and it navigates with a typed [MaterialPageRoute] to
  /// [BattleScreen] instead of a named route that was never registered.
  ///
  /// If the start fails (no questions, room refused, opponent gone) the
  /// presence entry this screen claimed is rolled back so the player stays
  /// visible and challengeable.
  Future<void> _startBattleWithOpponent({
    required String opponentUid,
    required String opponentName,
    required String opponentAvatar,
    required String difficulty,
    String? opponentAvatarUrl,
    String? challengeId,
  }) async {
    if (!mounted) return;

    // Claim the presence slot only while we really are in a battle.
    _presence.setAvailability(isAvailable: false, activity: 'battling');

    setState(() {
      _pendingChallengeToUid = null;
      _incomingChallenge = null;
      _outgoingChallenge = null;
    });

    final battle = context.read<BattleProvider>();
    final started = await battle.startBattleWithOpponent(
      opponentUid: opponentUid,
      opponentName: opponentName,
      opponentAvatar: opponentAvatarUrl?.isNotEmpty == true
          ? opponentAvatarUrl!
          : opponentAvatar,
      difficulty: _difficultyFrom(difficulty),
      challengeId: challengeId,
    );

    if (!started) {
      // Roll the presence claim back: the player is not battling after all.
      _presence.setAvailability(isAvailable: true, activity: 'idle');
      if (!mounted) return;
      _showSnackBar(battle.startError ?? 'Could not start the battle.');
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BattleScreen()),
    );
    // Returning from the arena frees the player for new challenges again.
    _presence.setAvailability(isAvailable: true, activity: 'idle');
    _watchOutgoingChallenge();
  }

  static BattleDifficulty _difficultyFrom(String value) {
    switch (value) {
      case 'easy':
        return BattleDifficulty.easy;
      case 'hard':
        return BattleDifficulty.hard;
      default:
        return BattleDifficulty.normal;
    }
  }

  // --------------------------------------------------------- UI Dialogs ---

  void _showIncomingChallengeDialog(ChallengeData challenge) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IncomingChallengeDialog(
        challenge: challenge,
        onAccept: () => _acceptChallenge(challenge),
        onReject: () => _rejectChallenge(challenge),
      ),
    );
  }

  void _showChallengeSentDialog(OnlineUser user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChallengeSentDialog(
        userName: user.name,
        userAvatar: user.effectiveAvatar,
        onCancel: _cancelOutgoingChallenge,
      ),
    );
  }

  void _showChallengeResultSnackbar(String name, String status) {
    String message;
    switch (status) {
      case 'rejected':
        message = '❌ $name declined your challenge';
      case 'expired':
        message = '⏰ Challenge to $name expired';
      case 'cancelled':
        message = 'Challenge cancelled';
      default:
        message = 'Challenge status: $status';
    }
    _showSnackBar(message);
  }

  void _showGuestRestrictionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🔒 Sign In Required',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'You need to sign in to challenge other players. '
          'Go to Profile → Sign In to create your account.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );
  }

  void _showDifficultySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚔️ Select Difficulty',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            for (final d in ['easy', 'normal', 'hard'])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                // Own Material so the tile ink paints above the sheet's
                // DecoratedBox (Flutter asserts otherwise).
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    tileColor: _selectedDifficulty == d
                        ? Colors.cyan.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading: Icon(
                      d == 'easy'
                          ? Icons.bolt
                          : d == 'normal'
                              ? Icons.balance
                              : Icons.local_fire_department,
                      color: d == 'easy'
                          ? Colors.green
                          : d == 'normal'
                              ? Colors.cyan
                              : Colors.orange,
                    ),
                    title: Text(d.toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                    trailing: _selectedDifficulty == d
                        ? const Icon(Icons.check_circle, color: Colors.cyan)
                        : null,
                    onTap: () {
                      setState(() => _selectedDifficulty = d);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF16213E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      final userProvider = context.read<UserProvider>();
      _presence.goOnline(
        uid: userProvider.user.userId,
        name: userProvider.user.username,
        avatar: userProvider.user.avatarPath,
        avatarUrl: userProvider.user.avatarUrl,
        level: userProvider.user.level,
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _presence.goOffline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceSub?.cancel();
    _incomingChallengeSub?.cancel();
    _outgoingChallengeSub?.cancel();
    _heartbeatTimer?.cancel();
    _presence.goOffline();
    super.dispose();
  }

  // --------------------------------------------------------- Build ------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        title: const Text('⚔️ Online Arena',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectedDifficulty == 'easy'
                      ? Icons.bolt
                      : _selectedDifficulty == 'normal'
                          ? Icons.balance
                          : Icons.local_fire_department,
                  color: _selectedDifficulty == 'easy'
                      ? Colors.green
                      : _selectedDifficulty == 'normal'
                          ? Colors.cyan
                          : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedDifficulty.toUpperCase(),
                  style: TextStyle(
                    color: _selectedDifficulty == 'easy'
                        ? Colors.green
                        : _selectedDifficulty == 'normal'
                            ? Colors.cyan
                            : Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            onPressed: _showDifficultySheet,
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0E21),
                  Color(0xFF1A1A2E),
                  Color(0xFF16213E),
                ],
              ),
            ),
          ),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.cyan),
            SizedBox(height: 16),
            Text('Scanning for players...',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    if (_onlineUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('No players online right now',
                style:
                    TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Try again in a few minutes!',
                style: TextStyle(color: Colors.white30, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _watchOnlineUsers();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan.withValues(alpha: 0.2),
                foregroundColor: Colors.cyan,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_onlineUsers.length} player${_onlineUsers.length != 1 ? 's' : ''} online',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BattleScreen(),
                    ),
                  );
                },
                icon:
                    const Icon(Icons.casino, color: Colors.amber, size: 18),
                label: const Text('Quick Match',
                    style:
                        TextStyle(color: Colors.amber, fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _onlineUsers.length,
            itemBuilder: (context, index) =>
                _buildUserTile(_onlineUsers[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildUserTile(OnlineUser user) {
    final isPendingToThis = _pendingChallengeToUid == user.uid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Stack(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CachedAvatar(
                    url: user.effectiveAvatar,
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1A1A2E), width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.stars,
                          size: 13, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text('Lv.${user.level}',
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 12)),
                      const SizedBox(width: 10),
                      Icon(_activityIcon(user.currentActivity),
                          size: 13, color: Colors.white38),
                      const SizedBox(width: 4),
                      Text(user.activityLabel,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            if (isPendingToThis)
              _buildPendingIndicator()
            else
              _buildChallengeButton(user),
          ],
        ),
      ),
    );
  }

  Widget _buildChallengeButton(OnlineUser user) {
    return GestureDetector(
      onTap: () => _sendChallenge(user),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE94560), Color(0xFFC62828)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE94560).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flash_on, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text('CHALLENGE',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingIndicator() {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.cyan),
          ),
          SizedBox(width: 8),
          Text('SENT',
              style: TextStyle(
                  color: Colors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  IconData _activityIcon(String activity) {
    switch (activity) {
      case 'idle':
        return Icons.hourglass_empty;
      case 'battling':
        return Icons.shield;
      case 'quiz':
        return Icons.quiz;
      case 'shop':
        return Icons.shopping_bag;
      default:
        return Icons.circle;
    }
  }
}

// ================================================================ Dialogs ===

/// Dialog shown to the receiver when they get a challenge.
class _IncomingChallengeDialog extends StatefulWidget {
  final ChallengeData challenge;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingChallengeDialog({
    required this.challenge,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_IncomingChallengeDialog> createState() =>
      _IncomingChallengeDialogState();
}

class _IncomingChallengeDialogState extends State<_IncomingChallengeDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int _timeLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _timeLeft = widget.challenge.secondsRemaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = widget.challenge.secondsRemaining;
      if (remaining <= 0) {
        _timer?.cancel();
        widget.onReject();
      } else {
        setState(() => _timeLeft = remaining);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: Colors.cyan.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.cyan.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚔️ BATTLE CHALLENGE!',
                style: TextStyle(
                  color: Colors.cyan,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + (_pulseController.value * 0.1);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.cyan, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyan.withValues(alpha: 0.4),
                          blurRadius:
                              15 + (_pulseController.value * 10),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage:
                          NetworkImage(widget.challenge.fromEffectiveAvatar),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(widget.challenge.fromName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Lv.${widget.challenge.fromLevel}',
                style:
                    const TextStyle(color: Colors.amber, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              'Difficulty: ${widget.challenge.difficulty.toUpperCase()}',
              style: TextStyle(
                color: widget.challenge.difficulty == 'easy'
                    ? Colors.green
                    : widget.challenge.difficulty == 'hard'
                        ? Colors.orange
                        : Colors.cyan,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _timeLeft <= 10
                    ? Colors.red.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '⏱ $_timeLeft seconds to respond',
                style: TextStyle(
                  color:
                      _timeLeft <= 10 ? Colors.red : Colors.white70,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onReject,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red, width: 1.5),
                      ),
                      child: const Center(
                        child: Text('✕ DECLINE',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onAccept,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF00B4D8),
                            Color(0xFF0077B6)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.cyan.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('⚔️ ACCEPT',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog shown to sender while waiting for acceptance.
class _ChallengeSentDialog extends StatefulWidget {
  final String userName;
  final String userAvatar;
  final VoidCallback onCancel;

  const _ChallengeSentDialog({
    required this.userName,
    required this.userAvatar,
    required this.onCancel,
  });

  @override
  State<_ChallengeSentDialog> createState() => _ChallengeSentDialogState();
}

class _ChallengeSentDialogState extends State<_ChallengeSentDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotsController;
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= 30) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: Colors.orange.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flash_on, size: 50, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Challenge sent to',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              widget.userName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _dotsController,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final delay = i * 0.2;
                    final value =
                        ((_dotsController.value + delay) % 1.0);
                    return Container(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.orange
                            .withValues(alpha: 0.3 + value * 0.7),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Waiting for response... ($_elapsed s)',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Colors.white24, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('CANCEL',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
