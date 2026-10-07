# iOS setup for PSBA IT Inventory

This project is developed on Windows. Apple's compiler and code-signing tools
only run on macOS, so the iOS build happens on Codemagic's Mac builders. The
configuration is in [`../codemagic.yaml`](../codemagic.yaml).

Nothing on the Android, Web, Firestore, authentication, inventory, permissions,
Local AI or OTA side is involved in any of this. iOS is a separate build target
that reuses the same Dart code unchanged.

## 1. The bundle identifier is a placeholder

The Xcode project currently uses:

```
com.psba.itinventory
```

**This is a placeholder.** It replaced Flutter's default `com.example.*`, which
Apple treats as reserved and which cannot be used for App Store distribution.
Confirm the identifier you actually want before the first signed build — it is
permanent once an App ID is registered and a build is uploaded.

It appears in six places in `Runner.xcodeproj/project.pbxproj` (three for the
app across Debug/Profile/Release, three for `RunnerTests`). To change it, run
this from the project root on Windows:

```bash
sed -i 's/com\.psba\.itinventory/YOUR.FINAL.BUNDLE.ID/g' ios/Runner.xcodeproj/project.pbxproj
```

Then update `bundle_identifier` in `codemagic.yaml` to the same value. The two
must match the App ID in your Apple Developer account exactly.

`lib/firebase_options.dart` has been reconciled with this identifier. Its `ios`
entry now carries the real `appId` of a Firebase iOS app registered for
`com.psba.itinventory`, fetched from Firebase rather than guessed. If you change
the identifier again, register the new one and update that entry too, or the
iOS build will be configured for an app that no longer matches its bundle.

The `macos` entry still points at the old `com.example.itManagementSystem`
registration. That was left alone deliberately: macOS is not a target of this
project, and nothing builds it.

## 2. Firebase on iOS: the plist is optional here

`lib/main.dart` calls:

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

The iOS configuration therefore comes from `lib/firebase_options.dart`, which is
compiled into the app. `GoogleService-Info.plist` is **not required** for the
app to start, sign in or reach Firestore on iOS.

You only need the plist if you later enable Analytics, Crashlytics, or App Check
on iOS, because those read it natively. If that happens, do not commit it —
store its base64 as a secure variable in Codemagic and uncomment the restore
step in `codemagic.yaml`.

## 3. What Apple will not let anyone else do for you

These require your identity, your payment method, or both:

| Item | Where it comes from | Needed for |
|---|---|---|
| Apple Developer Program membership, 99 USD/year | developer.apple.com, your Apple ID | Any signed build, TestFlight, App Store |
| Apple Team ID (10 characters) | Membership details page | Code signing |
| App ID registered for the final bundle identifier | Certificates, Identifiers & Profiles | Code signing |
| App Store Connect API key (.p8, Issuer ID, Key ID) | App Store Connect → Users and Access → Integrations | Letting Codemagic sign and upload automatically |
| An app record in App Store Connect | App Store Connect → My Apps | TestFlight distribution |

Nothing above has been guessed or filled in anywhere in this repository.

## 4. Two known iOS differences

**OTA updates do not work on iOS, and must not.** Apple does not permit
installing applications from outside the App Store. The updater in
`lib/core/ota/` is already restricted to Android by
`defaultTargetPlatform == TargetPlatform.android` in `ota_update_gate.dart`, so
on iOS it does nothing at all — no prompt, no network call. iOS releases go out
through TestFlight or the App Store instead. This was left exactly as it is.

**App Check on iOS attests through DeviceCheck.** `_activateAppCheck()` in
`lib/main.dart` now states `appleProvider` explicitly rather than relying on the
package default, which is `deviceCheck` in every build mode. A debug or profile
build cannot attest through DeviceCheck on the Simulator, so iOS follows the
same release/debug split Android already used.

Before an iPhone can pass App Check in a **debug** build, its debug token has to
be registered: run the app, copy the token it prints once to the console, and add
it under App Check → Apps → your iOS app → Manage debug tokens in the Firebase
console. Release builds need no such step. The Local AI server is unaffected
either way, because it authenticates with an API key rather than App Check.

## 5. Optional: Local AI over the local network

Not needed for the current setup, which reaches the Local AI server over its
public HTTPS Tailscale address. Only if you want an iPhone to reach the server
by its LAN address, iOS 14 and later additionally require this in
`Runner/Info.plist`, plus a one-time user prompt:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Used to reach the AI Assistant server on this network.</string>
```

## 6. Running the first build

Codemagic clones the **Git repository**. It cannot see the Windows working
directory, so commit and push first — otherwise the build is made from whatever
`origin/main` currently holds.

1. Sign in to codemagic.io with the GitHub account that owns
   `ranahasnain003-lab/it-management-system` and add the repository.
2. Codemagic detects `codemagic.yaml` automatically.
3. Start the **`ios-unsigned-verify`** workflow. It needs no Apple account and
   confirms the project compiles on macOS.
4. Only once that passes, complete the Apple items in step 3 and switch to the
   **`ios-testflight`** workflow.
