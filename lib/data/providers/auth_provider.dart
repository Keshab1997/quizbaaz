import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants/google_oauth.dart';
import '../../l10n/app_strings.dart';
import '../services/onesignal_service.dart';

/// A simple exception carrying a user-friendly message for the UI.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Handles Google Sign-In via Firebase Authentication.
class AuthProvider extends ChangeNotifier {
  bool _isBusy = false;
  String? _lastError;
  Future<void>? _initFuture;

  bool get isBusy => _isBusy;
  String? get lastError => _lastError;

  /// Firebase may not be ready (init timed out / offline). Never throw from
  /// a getter — the rest of the app must still render as a guest.
  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (e) {
      debugPrint('AuthProvider: FirebaseAuth unavailable – $e');
      return null;
    }
  }

  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;

  /// The signed-in Firebase user, or null when signed out.
  User? get firebaseUser {
    try {
      return _auth?.currentUser;
    } catch (_) {
      return null;
    }
  }

  bool get isSignedIn => firebaseUser != null;

  /// Initializes the Google Sign-In manager. Never blocks the first frame
  /// (called fire-and-forget from `main.dart`) and never throws.
  ///
  /// [serverClientId] is the Firebase **Web** client ID. Without it,
  /// `authenticate()` on Android does not return an ID token (Play-signed
  /// builds fail even after SHA-1 is added to Firebase).
  Future<void> initialize() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    try {
      await _googleSignIn
          .initialize(serverClientId: kGoogleServerClientId)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('AuthProvider: GoogleSignIn init failed – $e');
      _initFuture = null;
    }
  }

  /// Starts the Google sign-in flow.
  ///
  /// Returns true when signed in, false when the user cancelled the Google
  /// account picker, and throws an [AuthException] on failure.
  Future<bool> signInWithGoogle() async {
    _isBusy = true;
    _lastError = null;
    notifyListeners();

    try {
      debugPrint('AuthProvider: starting Google authenticate');
      await initialize();

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      debugPrint('AuthProvider: authenticate returned ${googleUser.email}');

      final String? idToken = googleUser.authentication.idToken;
      debugPrint(
        'AuthProvider: idToken ${idToken == null ? 'NULL' : 'present (${idToken.length} chars)'}',
      );
      if (idToken == null || idToken.isEmpty) {
        throw AuthException(S.authNoIdToken);
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);

      final auth = _auth;
      if (auth == null) {
        throw const AuthException(
          'Firebase is not ready yet. Check your internet connection and try again.',
        );
      }
      final userCredential = await auth.signInWithCredential(credential);
      debugPrint(
        'AuthProvider: Firebase sign-in ok uid=${userCredential.user?.uid}',
      );
      unawaited(OneSignalService.instance.syncFromHive());
      return userCredential.user != null;
    } on GoogleSignInException catch (e) {
      // google_sign_in 7 maps Play SHA mismatches to `canceled` with
      // description "[16] Account reauth failed" — not a real user cancel.
      debugPrint(
        'AuthProvider: GoogleSignInException code=${e.code} desc=${e.description}',
      );
      _lastError = _friendlyGoogleSignInError(e);
      if (_lastError != null) {
        throw AuthException(_lastError!);
      }
      return false;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthProvider: FirebaseAuth error ${e.code} - ${e.message}');
      _lastError = _friendlyAuthError(e);
      throw AuthException(_lastError ?? 'Sign-in failed.');
    } on AuthException catch (e) {
      _lastError = e.message;
      rethrow;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      _lastError = 'Google Sign-In failed. Please try again.';
      throw AuthException(_lastError!);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Signs out of both Google and Firebase.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore google sign-out errors (e.g. not signed in).
    }
    try {
      await _auth?.signOut();
    } catch (_) {}
    unawaited(Future(() async {
      await OneSignalService.instance.logout();
      await OneSignalService.instance.syncFromHive();
    }));
    notifyListeners();
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'This email is already linked to another sign-in method.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      case 'operation-not-allowed':
        return 'Google Sign-In is not enabled in Firebase. Enable it in '
            'Authentication → Sign-in method.';
      default:
        return 'Sign-in failed (${e.code}).';
    }
  }

  String _friendlyGoogleSignInError(GoogleSignInException e) {
    final code = e.code;
    final description = (e.description ?? '').toLowerCase();

    if (description.contains('[16]') ||
        description.contains('reauth') ||
        description.contains('10:') ||
        description.contains('developer error') ||
        description.contains('not authorized') ||
        description.contains('permission') ||
        description.contains('access_denied')) {
      return S.authReauthFailed;
    }

    if (code == GoogleSignInExceptionCode.canceled ||
        code == GoogleSignInExceptionCode.interrupted ||
        code == GoogleSignInExceptionCode.uiUnavailable) {
      return S.authSignInCanceled;
    }

    if (description.contains('network') ||
        description.contains('connection') ||
        description.contains('offline')) {
      return 'Network error. Check your internet connection and try again.';
    }

    debugPrint('GoogleSignInException: $code - ${e.description}');
    return 'Google Sign-In failed (${e.code}). Please try again.';
  }
}
