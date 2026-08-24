// This compile-safe placeholder is replaced by `flutterfire configure`.
// Do not commit real production configuration if your team policy forbids it.
// Firebase client configuration is not a server secret, but using FlutterFire
// keeps platform setup consistent.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('EkThikana starter is configured for Android first.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Run flutterfire configure for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD4mpH8JoJURwz4jVoDheg7pZ93SNtlYqk',
    appId: '1:412221245002:android:749fe1cbfd73b8927548b3',
    messagingSenderId: '412221245002',
    projectId: 'gochano-a30c8',
    storageBucket: 'gochano-a30c8.firebasestorage.app',
  );
}
