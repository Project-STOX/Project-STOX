# project_stox

Flutter inventory management application with Supabase-backed authentication and data services.

## Workspace Setup Status

- Flutter dependencies installed with `flutter pub get`.
- VS Code task created at `.vscode/tasks.json`:
	- `Flutter Analyze` -> runs `flutter analyze .`
- `copilot-instructions.md` checklist tracked at `.github/copilot-instructions.md`.

## Run and Debug

1. Install Flutter SDK and platform toolchains (Android/iOS/Web/Desktop as needed).
2. From workspace root, run:

```bash
flutter pub get
flutter run
```

3. For static diagnostics, run:

```bash
flutter analyze .
```

## Supabase Configuration

`lib/main.dart` reads these values using `String.fromEnvironment`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

You can provide them with `--dart-define`, for example:

```bash
flutter run --dart-define=SUPABASE_URL=<your_url> --dart-define=SUPABASE_ANON_KEY=<your_anon_key>
```

If no defines are passed, the current code includes fallback development defaults.
