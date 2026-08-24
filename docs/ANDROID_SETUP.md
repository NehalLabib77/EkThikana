# Android setup

Flutter targets Android for EkThikana. This doc covers the pieces the Flutter `flutter create` skeleton does not set up for you.

## 1. SDK packages

Install in Android Studio via SDK Manager:

- Android SDK Platform 34
- Android SDK Build-Tools 34.0.0
- Android SDK Platform-Tools
- Android SDK Command-line Tools (latest)
- Android Emulator (optional, recommended)

## 2. JDK

Flutter prefers JDK 17. Set in Android Studio:

```text
Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK = 17
```

## 3. Verify

```powershell
flutter doctor -v
```

Resolve every red X before continuing. Common items:

- "Android licenses not accepted" → `flutter doctor --android-licenses` (accept all).
- "cmdline-tools component is missing" → install via SDK Manager.
- "Android Studio not found" → set the `ANDROID_HOME` env var or open Android Studio once so it registers.

## 4. Application id

The application id is fixed at:

```text
com.ekthikana.ekthikana
```

Do not change it after publishing the first internal test build — Play Console treats it as a different app.

## 5. Notification permission (Android 13+)

`flutter_app/android/app/src/main/AndroidManifest.xml` declares:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

The runtime prompt is requested by `NotificationService` on first schedule. There is no need to ask earlier.

## 6. Signing key

For internal tests the debug key is enough. For Play Console:

1. Android Studio → Build → Generate Signed App Bundle / APK → APK.
2. Use **Create new…** for a release key. Keep the key + password outside the repo.
3. Add `key.properties` (gitignored) at `flutter_app/android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=C:/path/to/upload-keystore.jks
```

`flutter_app/android/app/build.gradle.kts` already references `key.properties` when present. Without it, `flutter build appbundle` falls back to debug signing.

## 7. Build commands

```powershell
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

The resulting `.aab` lives at `build/app/outputs/bundle/release/app-release.aab`. Upload it via Play Console → Internal testing.

## 8. App icon

`flutter_app/android/app/src/main/res/mipmap-*/ic_launcher.png` is the default Flutter icon. Replace it before the first public release. Recommended tool: `flutter_launcher_icons` package.

## 9. Notification icons

`@mipmap/ic_launcher` is used for notifications. For monochrome notification icons on Android 5+, add `flutter_app/android/app/src/main/res/drawable/ic_stat_notification.xml` and reference it from `NotificationService`.

## 10. APK size

Debug builds are large because they bundle every ABI. For Play Console, only the app bundle is needed — R8 minification is on by default. The bundle should be well under 25 MB.

## 11. Common build failures

### `Minimum supported Gradle version is X.Y`

Open `flutter_app/android/gradle/wrapper/gradle-wrapper.properties` and bump `distributionUrl` to match.

### `Manifest merger failed`

Likely two plugins declare the same permission. Search `android/app/src/main/AndroidManifest.xml` for duplicates.

### `Execution failed for task ':app:minifyReleaseWithR8'`

R8 stripped a class used reflectively. Add `-keep` rules to `app/proguard-rules.pro`. For most Flutter apps the defaults are enough.

### `INSTALL_FAILED_INSUFFICIENT_STORAGE` on emulator

Wipe data and restart the emulator, then `flutter run` again.

## 12. Local notifications on Android 12+

If a notification is delayed, check:

1. Battery optimisation is disabled for the app (Settings → Apps → EkThikana → Battery → Unrestricted).
2. The exact alarm permission is granted (Android 12+ shows this prompt when scheduling a one-shot).
