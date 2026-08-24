#!/usr/bin/env sh
set -e
flutter create . --platforms=android
flutter pub get
echo "Project prepared. Open it in Android Studio and press Run."
