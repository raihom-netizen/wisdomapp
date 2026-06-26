import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Opções por plataforma. iOS/Android nativos usam credenciais do app móvel (não as da web).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDLm_BNjBptj5ribo0YGHQ9Nqd4l_Inl-4',
    appId: '1:766524666378:web:13900906f683df187f25f3',
    messagingSenderId: '766524666378',
    projectId: 'wisdomapp-b9e98',
    authDomain: 'wisdomapp-b9e98.firebaseapp.com',
    storageBucket: 'wisdomapp-b9e98.firebasestorage.app',
    measurementId: 'G-Z6D218TWFY',
  );

  /// GoogleService-Info.plist (Runner) — obrigatório para `initializeApp` no IPA/TestFlight.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCdQ6AHag35hZxOeLYUV1CcjBKx8TZASgc',
    appId: '1:766524666378:ios:fb62985d27bf83747f25f3',
    messagingSenderId: '766524666378',
    projectId: 'wisdomapp-b9e98',
    storageBucket: 'wisdomapp-b9e98.firebasestorage.app',
    iosBundleId: 'com.wisdomapp',
    iosClientId:
        '766524666378-glgtv4te1i3s4fr67v1t89q57d2hcm9l.apps.googleusercontent.com',
  );

  /// `android/app/google-services.json` (package com.wisdomapp.app).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyArYbw1yW2qd1A85cWZxAVUh9jeusvt3Gc',
    appId: '1:766524666378:android:7d110291e6777aa37f25f3',
    messagingSenderId: '766524666378',
    projectId: 'wisdomapp-b9e98',
    storageBucket: 'wisdomapp-b9e98.firebasestorage.app',
  );

  static const FirebaseOptions macos = web;
  static const FirebaseOptions windows = web;
  static const FirebaseOptions linux = web;
}
