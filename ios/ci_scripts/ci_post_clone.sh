#!/bin/bash

# Navigate to the Flutter project directory
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "🚀 Starting Xcode Cloud post-clone script..."
echo "Repository path: $CI_PRIMARY_REPOSITORY_PATH"
echo "Current directory: $(pwd)"

# Install Flutter (if not already available in the environment)
if ! command -v flutter &> /dev/null
then
    echo "Flutter is not installed. Installing Flutter SDK..."
    git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
    export PATH="$PATH:$HOME/flutter/bin"
else
    echo "Flutter is already installed."
fi

# Verify Flutter installation
echo "✅ Flutter found: $(which flutter)"
flutter --version

# Install dependencies
echo "📦 Running Flutter pub get..."
# Install Flutter artifacts for iOS
flutter precache --ios

flutter pub get

echo "📦 Installing CocoaPods..."
# Install CocoaPods using Homebrew (disable auto-update to speed up)
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods || {
    echo "⚠️ Failed to install CocoaPods via Homebrew, trying alternative..."
    # If Homebrew fails, CocoaPods might already be available
    if ! command -v pod &> /dev/null; then
        echo "❌ CocoaPods not available"
        exit 1
    fi
}

# Set up CocoaPods for iOS
echo "📦 Running pod install for iOS..."
cd ios
pod install --repo-update

# Go back to the workspace root
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "✅ Post-clone script completed successfully!"
