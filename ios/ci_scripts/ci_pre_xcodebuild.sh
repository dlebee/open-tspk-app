#!/bin/sh
# This script runs before Xcode Cloud builds your app
# It sets up Flutter and CocoaPods dependencies

set -e

echo "🚀 Starting Xcode Cloud pre-build script..."

# Navigate to project root (Xcode Cloud sets CI_WORKSPACE)
cd "${CI_WORKSPACE:-.}"

# Check if Flutter is available
if ! command -v flutter >/dev/null 2>&1; then
  echo "⚠️ Flutter not found in PATH, attempting to find or install..."
  
  # Try to find Flutter in common locations
  if [ -d "/usr/local/flutter" ]; then
    export PATH="/usr/local/flutter/bin:$PATH"
    echo "✅ Found Flutter at /usr/local/flutter"
  elif [ -d "$HOME/flutter" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
    echo "✅ Found Flutter at $HOME/flutter"
  else
    echo "❌ Flutter SDK not found in standard locations."
    echo ""
    echo "For Xcode Cloud, you need to ensure Flutter is available. Options:"
    echo "1. Use a custom Docker image with Flutter pre-installed (recommended)"
    echo "2. Install Flutter in a custom location and update .xcode.env"
    echo "3. Add Flutter to PATH before this script runs"
    echo ""
    echo "Current PATH: $PATH"
    exit 1
  fi
fi

echo "✅ Flutter found: $(which flutter)"
flutter --version

# Get Flutter dependencies
echo "📦 Running flutter pub get..."
flutter pub get

# Generate Flutter files needed for iOS build
echo "🔧 Generating Flutter iOS files..."
flutter precache --ios

# Navigate to iOS directory
cd ios

# Install CocoaPods dependencies
echo "📦 Running pod install..."
if ! command -v pod >/dev/null 2>&1; then
  echo "⚠️ CocoaPods not found in PATH"
  # Try using bundler if Gemfile exists, or try installing
  if [ -f "Gemfile" ]; then
    bundle install
    bundle exec pod install --repo-update
  else
    echo "❌ CocoaPods not available. Xcode Cloud should have it pre-installed."
    exit 1
  fi
else
  pod install --repo-update
fi

echo "✅ Pre-build script completed successfully!"
