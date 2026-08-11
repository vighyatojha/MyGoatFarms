import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDZdySTm9seobFg51AXNvDOSi4pF4ZMYq4',
    appId: '1:694889896033:web:9834bde20e9ca1f09df220',
    messagingSenderId: '694889896033',
    projectId: 'mygoatfarms-5813a',
    authDomain: 'mygoatfarms-5813a.firebaseapp.com',
    storageBucket: 'mygoatfarms-5813a.firebasestorage.app',
    measurementId: 'G-4SK1DS3QB9',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBgySo795nAnFphY8H7vXmdW7cUoT7UL-A',
    appId: '1:694889896033:android:bf988055daf2eb739df220',
    messagingSenderId: '694889896033',
    projectId: 'mygoatfarms-5813a',
    storageBucket: 'mygoatfarms-5813a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAyctdOncmpR1vglGfTLNnISjjQgPzgd1g',
    appId: '1:694889896033:ios:b3581e7f226969e99df220',
    messagingSenderId: '694889896033',
    projectId: 'mygoatfarms-5813a',
    storageBucket: 'mygoatfarms-5813a.firebasestorage.app',
    iosBundleId: 'com.example.mygoatfarms',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDZdySTm9seobFg51AXNvDOSi4pF4ZMYq4',
    appId: '1:694889896033:web:b103cbef6d5929d79df220',
    messagingSenderId: '694889896033',
    projectId: 'mygoatfarms-5813a',
    authDomain: 'mygoatfarms-5813a.firebaseapp.com',
    storageBucket: 'mygoatfarms-5813a.firebasestorage.app',
    measurementId: 'G-EJ9X7P8E0V',
  );
}
