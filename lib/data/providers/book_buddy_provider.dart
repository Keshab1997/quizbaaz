import 'dart:async';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ocr_ai_bridge/smart_ocr_ai_bridge.dart';

import '../../l10n/app_strings.dart';
import '../models/app_config.dart';
import '../models/book_study_session.dart';
import '../models/question_model.dart';
import '../services/book_buddy_service.dart';
import '../services/competition_clock.dart';
import '../services/firestore_service.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';

/// State owner for AI Book Buddy (`BookBuddyScreen`).
///
/// Follows QuizBaaz's core architecture rules:
/// * Reads and writes `HiveService` directly so study sessions, the student's
///   chosen AI reply language (`en` / `bn` / `hi`), reading font scale, and
///   daily usage quota survive restarts and work completely offline.
/// * Enforces the Admin-configured daily limit (`AppConfig.bookBuddyDailyLimit`
///   from Firestore `config/app` + Hive cache) per IST competition day
///   (`CompetitionClock.dateKey`) while keeping saved notes & practice quiz
///   replays completely free.
class BookBuddyProvider extends ChangeNotifier {
  BookBuddyProvider({BookBuddyService? service, DateTime Function()? clock})
    : _service =
          service ?? BookBuddyService(keyManager: ApiKeyManager.instance),
      _clock = clock ?? DateTime.now {
    _loadPreferences();
    reloadSessions();
  }

  final BookBuddyService _service;
  final DateTime Function() _clock;

  static const double minTextScale = 0.9;
  static const double maxTextScale = 1.35;
  static const double defaultTextScale = 1.08;

  List<BookStudySession> _savedSessions = const [];
  BookStudySession? _activeSession;
  Uint8List? _activeImageBytes;

  String _replyLanguage = 'bn';
  double _textScale = defaultTextScale;

  int _dailyLimit = const AppConfig().bookBuddyDailyLimit;
  bool _adminUnlimited = const AppConfig().bookBuddyAdminUnlimited;
  bool _isAdminUser = false;
  String _usageDateKey = '';
  int _usedToday = 0;

  bool _isScanning = false;
  bool _isAsking = false;
  bool _isGeneratingMcqs = false;
  String? _errorMessage;

  List<BookStudySession> get savedSessions => _savedSessions;
  BookStudySession? get activeSession => _activeSession;
  Uint8List? get activeImageBytes => _activeImageBytes;

  /// Dedicated AI tutor & MCQ language (`en`, `bn`, or `hi`), independent of
  /// the global app UI language so an English-UI student can still study in
  /// Bengali or Hindi.
  String get replyLanguage => _replyLanguage;

  /// Reader text scale multiplier (`0.9` to `1.35`).
  double get textScale => _textScale;

  /// Admin-configured daily AI Book Buddy limit (`0` = paused).
  int get dailyLimit => _dailyLimit;

  /// Whether admin accounts bypass [dailyLimit].
  bool get adminUnlimited => _adminUnlimited;

  /// True when the current signed-in user is an admin with unlimited bypass on.
  bool get isUnlimitedForUser => _isAdminUser && _adminUnlimited;

  /// True when Admin has set the daily limit to `0` (paused for regular users).
  bool get isPausedByAdmin => !isUnlimitedForUser && _dailyLimit <= 0;

  /// Number of AI Book Buddy actions used on today's IST competition day.
  int get usedToday {
    _refreshUsageBucketIfNeeded();
    return _usedToday;
  }

  /// Remaining AI Book Buddy actions available today (`0` when exhausted/paused).
  int get remainingToday {
    if (isUnlimitedForUser) return 999;
    final left = _dailyLimit - usedToday;
    return left < 0 ? 0 : left;
  }

  /// True when the student has used up all allowed AI actions for today.
  bool get isQuotaExhausted =>
      !isUnlimitedForUser && (_dailyLimit <= 0 || usedToday >= _dailyLimit);

  bool get isScanning => _isScanning;
  bool get isAsking => _isAsking;
  bool get isGeneratingMcqs => _isGeneratingMcqs;
  bool get isBusy => _isScanning || _isAsking || _isGeneratingMcqs;
  String? get errorMessage => _errorMessage;

  String _todayKey() => CompetitionClock.dateKey(_clock());

  void _loadPreferences() {
    _usageDateKey = _todayKey();
    if (!HiveService.isInitialized) {
      _replyLanguage = kSupportedLanguageCodes.contains(S.code) ? S.code : 'bn';
      return;
    }
    final savedLang = HiveService.getMeta<String>(
      HiveService.metaBookBuddyLanguage,
    );
    if (savedLang != null && kSupportedLanguageCodes.contains(savedLang)) {
      _replyLanguage = savedLang;
    } else {
      _replyLanguage = kSupportedLanguageCodes.contains(S.code) ? S.code : 'bn';
    }

    final savedScale = HiveService.getMeta<double>(
      HiveService.metaBookBuddyTextScale,
    );
    if (savedScale != null) {
      _textScale = savedScale.clamp(minTextScale, maxTextScale);
    }

    final cachedCfg = SyncService.cachedConfig();
    _dailyLimit = cachedCfg.bookBuddyDailyLimit;
    _adminUnlimited = cachedCfg.bookBuddyAdminUnlimited;

    final storedDate = HiveService.getMeta<String>(
      HiveService.metaBookBuddyUsageDate,
    );
    final storedCount =
        HiveService.getMeta<int>(HiveService.metaBookBuddyUsageCount) ?? 0;
    if (storedDate == _usageDateKey) {
      _usedToday = storedCount < 0 ? 0 : storedCount;
    } else {
      _usedToday = 0;
    }
  }

  void _refreshUsageBucketIfNeeded() {
    final today = _todayKey();
    if (_usageDateKey == today) return;
    _usageDateKey = today;
    _usedToday = 0;
    if (HiveService.isInitialized) {
      unawaited(HiveService.setMeta(HiveService.metaBookBuddyUsageDate, today));
      unawaited(HiveService.setMeta(HiveService.metaBookBuddyUsageCount, 0));
    }
  }

  /// Syncs the Admin-configured limit from [config] and optionally reconciles
  /// today's usage count with Firestore (`users/{uid}/meta/book_buddy_usage`)
  /// so reinstalling or switching devices cannot bypass the daily cap.
  Future<void> syncQuotaPolicy({
    required AppConfig config,
    required bool isAdmin,
    String userId = '',
    bool pullRemote = true,
  }) async {
    _refreshUsageBucketIfNeeded();
    var changed = false;

    if (_dailyLimit != config.bookBuddyDailyLimit ||
        _adminUnlimited != config.bookBuddyAdminUnlimited ||
        _isAdminUser != isAdmin) {
      _dailyLimit = config.bookBuddyDailyLimit;
      _adminUnlimited = config.bookBuddyAdminUnlimited;
      _isAdminUser = isAdmin;
      changed = true;
    }

    if (pullRemote && SyncService.isOnline) {
      final freshCfg = await SyncService.pullConfig();
      if (freshCfg != null &&
          (_dailyLimit != freshCfg.bookBuddyDailyLimit ||
              _adminUnlimited != freshCfg.bookBuddyAdminUnlimited)) {
        _dailyLimit = freshCfg.bookBuddyDailyLimit;
        _adminUnlimited = freshCfg.bookBuddyAdminUnlimited;
        changed = true;
      }

      if (userId.isNotEmpty && userId != 'guest') {
        final today = _todayKey();
        final remoteCount = await FirestoreService.loadBookBuddyDailyUsage(
          userId,
          today,
        );
        if (remoteCount != null && remoteCount > _usedToday) {
          _usedToday = remoteCount;
          if (HiveService.isInitialized) {
            await HiveService.setMeta(
              HiveService.metaBookBuddyUsageDate,
              today,
            );
            await HiveService.setMeta(
              HiveService.metaBookBuddyUsageCount,
              _usedToday,
            );
          }
          changed = true;
        }
      }
    }

    if (changed) notifyListeners();
  }

  /// Checks whether the user may spend 1 AI action right now; sets
  /// [_errorMessage] (`paused_by_admin` or `daily_limit_reached`) if blocked.
  bool _checkDailyQuotaAllowed() {
    _refreshUsageBucketIfNeeded();
    if (isUnlimitedForUser) return true;
    if (_dailyLimit <= 0) {
      _errorMessage = 'paused_by_admin';
      notifyListeners();
      return false;
    }
    if (_usedToday >= _dailyLimit) {
      _errorMessage = 'daily_limit_reached';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Records 1 successful AI action against today's quota in Hive + Firestore.
  Future<void> _recordQuotaUsage(String userId) async {
    _refreshUsageBucketIfNeeded();
    _usedToday += 1;
    final today = _usageDateKey;
    if (HiveService.isInitialized) {
      await HiveService.setMeta(HiveService.metaBookBuddyUsageDate, today);
      await HiveService.setMeta(
        HiveService.metaBookBuddyUsageCount,
        _usedToday,
      );
    }
    if (userId.isNotEmpty &&
        userId != 'student' &&
        userId != 'guest' &&
        SyncService.isOnline) {
      unawaited(
        FirestoreService.saveBookBuddyDailyUsage(
          userId,
          dateKey: today,
          count: _usedToday,
        ),
      );
    }
  }

  /// Updates the dedicated AI reply & MCQ language (`en` / `bn` / `hi`) and
  /// persists the choice in Hive.
  Future<void> setReplyLanguage(String code) async {
    if (!kSupportedLanguageCodes.contains(code) || _replyLanguage == code) {
      return;
    }
    _replyLanguage = code;
    if (HiveService.isInitialized) {
      await HiveService.setMeta(HiveService.metaBookBuddyLanguage, code);
    }
    notifyListeners();
  }

  /// Adjusts the reading font scale by [delta] (clamped to `[0.9, 1.35]`).
  Future<void> adjustTextScale(double delta) async {
    final next = (_textScale + delta).clamp(minTextScale, maxTextScale);
    if ((next - _textScale).abs() < 0.01) return;
    _textScale = next;
    if (HiveService.isInitialized) {
      unawaited(
        HiveService.setMeta(HiveService.metaBookBuddyTextScale, _textScale),
      );
    }
    notifyListeners();
  }

  /// Reloads saved study sessions from Hive.
  void reloadSessions() {
    _savedSessions = HiveService.loadBookStudySessions();
    notifyListeners();
  }

  /// Clears any displayed error banner.
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Resets the current workspace so the student can scan a fresh page.
  void startNewScan() {
    _activeSession = null;
    _activeImageBytes = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Opens a previously saved [BookStudySession] from Hive (0 tokens, offline).
  void openSavedSession(BookStudySession session) {
    _activeSession = session;
    _activeImageBytes = null;
    _errorMessage = null;
    if (kSupportedLanguageCodes.contains(session.replyLanguage)) {
      _replyLanguage = session.replyLanguage;
    }
    notifyListeners();
  }

  /// Deletes a saved session from Hive.
  Future<void> deleteSession(String sessionId) async {
    await HiveService.deleteBookStudySession(sessionId);
    if (_activeSession?.id == sessionId) {
      _activeSession = null;
      _activeImageBytes = null;
    }
    _savedSessions = HiveService.loadBookStudySessions();
    notifyListeners();
  }

  /// Scans [imageBytes] with `SmartOcrAiBridge`, explains the page in
  /// [languageCode] (defaults to [replyLanguage]), and persists the new
  /// [BookStudySession] in Hive.
  Future<bool> scanBookPage({
    required Uint8List imageBytes,
    String? languageCode,
    required String defaultTitle,
    required String initialQuestionLabel,
    String? customPrompt,
    String userId = 'student',
  }) async {
    if (!_checkDailyQuotaAllowed()) return false;

    final targetLang = languageCode ?? _replyLanguage;
    _isScanning = true;
    _errorMessage = null;
    _activeImageBytes = imageBytes;
    notifyListeners();

    try {
      final analysis = await _service.scanAndExplainPage(
        imageBytes: imageBytes,
        languageCode: targetLang,
        customQuestion: customPrompt,
        userId: userId,
      );

      final nowMs = _clock().millisecondsSinceEpoch;
      final session = BookStudySession(
        id: 'book_$nowMs',
        title: analysis.title.isNotEmpty ? analysis.title : defaultTitle,
        extractedText: analysis.extractedText,
        ocrScore: analysis.ocrScore,
        usedVisionFallback: analysis.usedVisionFallback,
        tokenSavingsLabel: analysis.tokenSavingsLabel,
        replyLanguage: targetLang,
        turns: [
          BookChatTurn(
            question:
                (customPrompt != null && customPrompt.trim().isNotEmpty)
                    ? customPrompt.trim()
                    : initialQuestionLabel,
            answer: analysis.explanation,
            createdAtMs: nowMs,
          ),
        ],
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
      );

      await _recordQuotaUsage(userId);
      await HiveService.saveBookStudySession(session);
      _activeSession = session;
      _savedSessions = HiveService.loadBookStudySessions();
      return true;
    } on SmartOcrAiBridgeException catch (e) {
      _errorMessage = _friendlyBridgeError(e);
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Sends a follow-up question on the active page and appends the AI answer.
  Future<bool> askQuestion({
    required String question,
    String? languageCode,
    String userId = 'student',
  }) async {
    final current = _activeSession;
    final trimmed = question.trim();
    if (current == null || trimmed.isEmpty) return false;
    if (!_checkDailyQuotaAllowed()) return false;

    final targetLang = languageCode ?? _replyLanguage;

    _isAsking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final answer = await _service.askFollowUp(
        question: trimmed,
        extractedText: current.extractedText,
        fallbackImageBytes: _activeImageBytes,
        languageCode: targetLang,
        userId: userId,
      );

      final nowMs = _clock().millisecondsSinceEpoch;
      final updated = current.copyWith(
        replyLanguage: targetLang,
        turns: [
          ...current.turns,
          BookChatTurn(question: trimmed, answer: answer, createdAtMs: nowMs),
        ],
        updatedAtMs: nowMs,
      );

      await _recordQuotaUsage(userId);
      await HiveService.saveBookStudySession(updated);
      _activeSession = updated;
      _savedSessions = HiveService.loadBookStudySessions();
      return true;
    } on SmartOcrAiBridgeException catch (e) {
      _errorMessage = _friendlyBridgeError(e);
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isAsking = false;
      notifyListeners();
    }
  }

  /// Generates [count] practice MCQs for the active session and saves them to Hive.
  Future<List<QuestionModel>> generateMcqs({
    String? languageCode,
    int count = 5,
    String userId = 'student',
  }) async {
    final current = _activeSession;
    if (current == null) return const [];
    if (!_checkDailyQuotaAllowed()) return const [];

    final targetLang = languageCode ?? _replyLanguage;

    _isGeneratingMcqs = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final mcqs = await _service.generatePracticeMcqs(
        extractedText: current.extractedText,
        fallbackImageBytes: _activeImageBytes,
        languageCode: targetLang,
        count: count,
        userId: userId,
      );

      if (mcqs.isEmpty) {
        _errorMessage = 'empty_mcq';
        return const [];
      }

      final nowMs = _clock().millisecondsSinceEpoch;
      final updated = current.copyWith(
        replyLanguage: targetLang,
        generatedMcqs: mcqs,
        updatedAtMs: nowMs,
      );

      await _recordQuotaUsage(userId);
      await HiveService.saveBookStudySession(updated);
      _activeSession = updated;
      _savedSessions = HiveService.loadBookStudySessions();
      return mcqs;
    } on SmartOcrAiBridgeException catch (e) {
      _errorMessage = _friendlyBridgeError(e);
      return const [];
    } catch (e) {
      _errorMessage = e.toString();
      return const [];
    } finally {
      _isGeneratingMcqs = false;
      notifyListeners();
    }
  }

  static String _friendlyBridgeError(SmartOcrAiBridgeException e) {
    final lower = e.message.toLowerCase();
    if (lower.contains('no healthy api keys') ||
        lower.contains('no keypooladapter')) {
      return 'no_api_key';
    }
    return e.message;
  }
}
