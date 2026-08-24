@echo off
where flutter >nul 2>nul || (echo Flutter SDK is not in PATH & pause & exit /b 1)
flutter create . --platforms=android
flutter pub get
echo Project prepared. Open this folder in Android Studio and press Run.
pause
