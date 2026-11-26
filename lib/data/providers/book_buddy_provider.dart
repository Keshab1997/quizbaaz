import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ocr_ai_bridge/smart_ocr_ai_bridge.dart';

import '../models/book_study_session.dart';
import '../models/question_model.dart';
import '../services/book_buddy_service.dart';
import '../services/hive_service.dart';

/// State owner for AI Book Buddy (`BookBuddyScreen`).
///
/// Follows QuizBaaz's core architecture rules:
/// * Reads and writes `HiveService` directly so study sessions survive restarts
///   and work completely offline once saved.
/// * Holds transient image bytes in memory for vision fallback when a page has
///   no machine-readable OCR text, while persisting compacted text, Q&A turns,
///   and generated MCQs in Hive.
class BookBuddyProvider extends ChangeNotifier {
  BookBuddyProvider({BookBuddyService? service})
    : _service =
          service ?? BookBuddyService(keyManager: ApiKeyManager.instance) {
    reloadSessions();
  }

  final BookBuddyService _service;

  List<BookStudySession> _savedSessions = const [];
  BookStudySession? _activeSession;
  Uint8List? _activeImageBytes;

  bool _isScanning = false;
  bool _isAsking = false;
  bool _isGeneratingMcqs = false;
  String? _errorMessage;

  List<BookStudySession> get savedSessions => _savedSessions;
  BookStudySession? get activeSession => _activeSession;
  Uint8List? get activeImageBytes => _activeImageBytes;

  bool get isScanning => _isScanning;
  bool get isAsking => _isAsking;
  bool get isGeneratingMcqs => _isGeneratingMcqs;
  bool get isBusy => _isScanning || _isAsking || _isGeneratingMcqs;
  String? get errorMessage => _errorMessage;

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
  /// [languageCode], and persists the new [BookStudySession] in Hive.
  Future<bool> scanBookPage({
    required Uint8List imageBytes,
    required String languageCode,
    required String defaultTitle,
    required String initialQuestionLabel,
    String? customPrompt,
    String userId = 'student',
  }) async {
    _isScanning = true;
    _errorMessage = null;
    _activeImageBytes = imageBytes;
    notifyListeners();

    try {
      final analysis = await _service.scanAndExplainPage(
        imageBytes: imageBytes,
        languageCode: languageCode,
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
    required String languageCode,
    String userId = 'student',
  }) async {
    final current = _activeSession;
    final trimmed = question.trim();
    if (current == null || trimmed.isEmpty) return false;

    _isAsking = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final answer = await _service.askFollowUp(
        question: trimmed,
        extractedText: current.extractedText,
        fallbackImageBytes: _activeImageBytes,
        languageCode: languageCode,
        userId: userId,
      );

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updated = current.copyWith(
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
    required String languageCode,
    int count = 5,
    String userId = 'student',
  }) async {
    final current = _activeSession;
    if (current == null) return const [];

    _isGeneratingMcqs = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final mcqs = await _service.generatePracticeMcqs(
        extractedText: current.extractedText,
        fallbackImageBytes: _activeImageBytes,
        languageCode: languageCode,
        count: count,
        userId: userId,
      );

      if (mcqs.isEmpty) {
        _errorMessage = 'empty_mcq';
        return const [];
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updated = current.copyWith(generatedMcqs: mcqs, updatedAtMs: nowMs);

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
