// Manual Firebase options for Quizbaaz project (quizbaaz-740bd)
// These are derived from the google-services.json and Firebase project config.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // Default to Android options; for other platforms, add accordingly.
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDnZ1SjoFZkN4Fxl3z5fJjqXhYisObXw5Q',
    appId: '1:274398480008:android:9e2c02e85be45331b8413d',
    messagingSenderId: '274398480008',
    projectId: 'quizbaaz-740bd',
    storageBucket: 'quizbaaz-740bd.firebasestorage.app',
  );

  // Add iOS/web options here when needed.
}
