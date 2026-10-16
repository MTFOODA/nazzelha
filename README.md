# Nazzelha

Nazzelha is a Flutter application for downloading videos from supported
services. The project includes Android, Windows, and web targets, with a
Python backend for desktop downloads.

## Getting started

Install Flutter and run:

```bash
flutter pub get
flutter run
```

For Python backend setup and desktop-specific details, see
[python_backend/README.md](python_backend/README.md).

Android builds require host Python 3.11 for Chaquopy. If `python` on `PATH`
does not resolve to Python 3.11, set `CHAQUOPY_BUILD_PYTHON` to the Python 3.11
executable before building.
