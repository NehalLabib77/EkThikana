# Android notifications

EkThikana uses `flutter_local_notifications` for task reminders.

The included Windows bootstrap script prepares the current Android shell with:

- Android 13+ notification permission
- boot-completed permission
- scheduled notification receiver
- boot receiver
- Java 17
- core-library desugaring
- minimum Android SDK 24
- a small notification icon named `app_icon`

The application schedules reminders using **inexact** alarms, so it intentionally does not request exact-alarm permission.

## If you regenerate `android/`

Run:

```powershell
..\tool\bootstrap_flutter_windows.ps1
```

again before re-running `flutterfire configure`.

## Local HTTP testing

The generated debug manifest permits cleartext HTTP only for debug builds so your Android phone can connect to a local FastAPI server such as:

```text
http://192.168.0.105:8000
```

Production builds do not enable cleartext traffic and should use your HTTPS Render URL.
