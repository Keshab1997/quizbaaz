/// Web OAuth client ID from Firebase (`google-services.json` → oauth_client
/// `client_type: 3`). google_sign_in 7 needs this as [serverClientId] or
/// Android never mints an ID token and Firebase Auth fails even when SHA-1
/// fingerprints are correct.
const String kGoogleServerClientId =
    '274398480008-rkvm5k4nrkbqsa7rh0468kgpk8e4shm6.apps.googleusercontent.com';
