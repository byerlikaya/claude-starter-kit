# Isolates, platform channels, navigation, text and release (Flutter)

Checked against https://docs.flutter.dev/perf/isolates, https://docs.flutter.dev/platform-integration/platform-channels,
https://docs.flutter.dev/ui/navigation,
https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization,
https://docs.flutter.dev/testing/overview, https://docs.flutter.dev/testing/integration-tests,
https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html, https://docs.flutter.dev/deployment/obfuscate,
https://dart.dev/tools/dart-format and https://dart.dev/tools/pub/private-files (2026-10-02).

## Isolates
- The one hard rule: use an isolate when a computation makes the UI jank — when it takes longer than the gap between
  two frames. Typical: decoding or parsing a large file, image/audio/video work, a large local query.
- One-off work: `Isolate.run(() => …)` or `compute(fn, message)`. A long-lived worker: `Isolate.spawn` with a
  `ReceivePort` / `SendPort` pair.
- A spawned isolate has no `rootBundle` and does no widget or UI work. Plugins can be used there through
  `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken.instance!)` (sending works; unsolicited
  messages from the host do not arrive).
- The web has no isolates. `compute` still compiles there and runs on the main thread.

## Platform channels
- `MethodChannel` (calls), `EventChannel` (streams), `BasicMessageChannel` (messages); all asynchronous, encoded by
  `StandardMessageCodec` (booleans, numbers, strings, typed byte lists, lists, maps, null).
- The Dart side catches `PlatformException` (the platform returned an error) and `MissingPluginException` (no
  implementation on this platform) and decides what the UI shows — the `frontend` rule of explicit error paths.
- The native handler runs on the platform's main thread (Android: the UI thread; iOS: the main thread).
- Prefer `pigeon`: the messages are generated and typed, so the two sides cannot drift on a method name.
- Render by capability: a feature a platform lacks is not offered there.

## Navigation
- `Navigator` push/pop for a simple stack. An app with deep links, the web, or several navigators uses a routing
  package that parses the path (the project's own; `go_router` is the one Flutter's docs name).
- Named routes (`routes:` with `pushNamed`) are not recommended: their deep-link behaviour cannot be customised and
  the browser's forward button does not work with them.

## Text and locales
- `flutter_localizations` and `intl` in `pubspec.yaml`, `generate: true` under `flutter:`, an `l10n.yaml` with
  `arb-dir`, `template-arb-file`, `output-localization-file`. `flutter gen-l10n` (or `flutter pub get` / `run`)
  generates `AppLocalizations`.
- Placeholders, plurals and selects are ICU messages in the ARB file (`{count, plural, =0{…} other{…}}`), never
  strings glued together in Dart. `MaterialApp` gets `localizationsDelegates` and `supportedLocales`.

## Tests
- Unit (logic, dependencies faked), widget (one widget's look and interaction), integration (`integration_test/`, the
  `integration_test` SDK package as a dev dependency, `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`,
  `flutter test integration_test`). Confidence and maintenance cost both rise from unit to integration; a well-tested
  app has many unit and widget tests and enough integration tests for its important flows.
- Golden files: `matchesGoldenFile('goldens/x.png')`, refreshed with `flutter test --update-goldens`. The default
  test font (Ahem) draws boxes; custom fonts render differently across platforms and Flutter versions, so goldens are
  produced and compared on one platform, with fonts loaded first (`flutter_test_config.dart`).

## Release
- `flutter build <target> --obfuscate --split-debug-info=<dir>` on the targets that support it (Android, iOS, macOS,
  Linux, Windows; not the web). Keep the symbols: `flutter symbolize -i <trace> -d <symbols>` reads a stack trace
  back. Code that matches on type names (`runtimeType.toString()`) breaks under obfuscation.
- Obfuscation renames symbols; it does not encrypt and does not stop reverse engineering. **A secret does not ship in
  the app**, whatever the build flags.
- An application commits `pubspec.lock` (a library package does not): transitive upgrades become visible changes.
- `dart format` rewrites files by default; in CI and in the DoD use `dart format --set-exit-if-changed .` (exit 1
  when anything would change). The line width is the project's `formatter` setting in `analysis_options.yaml`.
