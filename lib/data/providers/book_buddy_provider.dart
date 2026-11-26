import 'dart:async';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ocr_ai_bridge/smart_ocr_ai_bridge.dart';

import '../../l10n/app_strings.dart';
import '../models/book_study_session.dart';
import '../models/question_model.dart';
import '../services/book_buddy_service.dart';
import '../services/hive_service.dart';

/// State owner for AI Book Buddy (`BookBuddyScreen`).
///
/// Follows QuizBaaz's core architecture rules:
/// * Reads and writes `HiveService` directly so study sessions, the student's
///   chosen AI reply language (`en` / `bn` / `hi`), and reading font scale
///   survive restarts and work completely offline.
/// * Holds transient image bytes in memory for vision fallback when a page has
///   no machine-readable OCR text, while persisting compacted text, Q&A turns,
///   and generated MCQs in Hive.
class BookBuddyProvider extends ChangeNotifier {
  BookBuddyProvider({BookBuddyService? service})
    : _service =
          service ?? BookBuddyService(keyManager: ApiKeyManager.instance) {
    _loadPreferences();
    reloadSessions();
  }

  final BookBuddyService _service;

  static const double minTextScale = 0.9;
  static const double maxTextScale = 1.35;
  static const double defaultTextScale = 1.08;

  List<BookStudySession> _savedSessions = const [];
  BookStudySession? _activeSession;
  Uint8List? _activeImageBytes;

  String _replyLanguage = 'bn';
  double _textScale = defaultTextScale;

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

  bool get isScanning => _isScanning;
  bool get isAsking => _isAsking;
  bool get isGeneratingMcqs => _isGeneratingMcqs;
  bool get isBusy => _isScanning || _isAsking || _isGeneratingMcqs;
  String? get errorMessage => _errorMessage;

  void _loadPreferences() {
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

      final nowMs = DateTime.now().millisecondsSinceEpoch;
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

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updated = current.copyWith(
        replyLanguage: targetLang,
        turns: [
          ...current.turns,
          BookChatTurn(question: trimmed, answer: answer, createdAtMs: nowMs),
        ],
        updatedAtMs: nowMs,
      );

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

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updated = current.copyWith(
        replyLanguage: targetLang,
        generatedMcqs: mcqs,
        updatedAtMs: nowMs,
      );

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
