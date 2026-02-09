#!/bin/sh
# This script runs before Xcode Cloud builds your app
# It sets up Flutter and CocoaPods dependencies

set -e

echo "🚀 Starting Xcode Cloud pre-build script..."
echo "Working directory: $(pwd)"
echo "CI_WORKSPACE: ${CI_WORKSPACE:-not set}"

# Navigate to project root (Xcode Cloud sets CI_WORKSPACE)
# CI_WORKSPACE points to the root of the repository
if [ -n "$CI_WORKSPACE" ]; then
  if [ -d "$CI_WORKSPACE" ]; then
    cd "$CI_WORKSPACE"
    echo "Changed to CI_WORKSPACE: $(pwd)"
  else
    echo "⚠️ CI_WORKSPACE directory does not exist: $CI_WORKSPACE"
    echo "Using current directory: $(pwd)"
  fi
else
  echo "⚠️ CI_WORKSPACE not set, using current directory: $(pwd)"
  # Try to find the project root by looking for pubspec.yaml
  if [ ! -f "pubspec.yaml" ]; then
    # We might be in a subdirectory, try going up
    if [ -f "../pubspec.yaml" ]; then
      cd ..
      echo "Found project root: $(pwd)"
    fi
  fi
fi

# Function to install Flutter
install_flutter() {
  echo "📥 Installing Flutter SDK..."
  FLUTTER_VERSION="stable"
  FLUTTER_INSTALL_DIR="$HOME/flutter"
  
  # Check if git is available
  if ! command -v git >/dev/null 2>&1; then
    echo "❌ Git is required to install Flutter but not found"
    return 1
  fi
  
  # Clone Flutter if it doesn't exist
  if [ ! -d "$FLUTTER_INSTALL_DIR" ]; then
    echo "Cloning Flutter from GitHub (this may take a few minutes)..."
    if ! git clone https://github.com/flutter/flutter.git -b $FLUTTER_VERSION "$FLUTTER_INSTALL_DIR" --depth 1; then
      echo "❌ Failed to clone Flutter repository"
      return 1
    fi
  else
    echo "Flutter directory exists, updating..."
    cd "$FLUTTER_INSTALL_DIR"
    if ! git fetch --depth 1 || ! git checkout $FLUTTER_VERSION; then
      echo "⚠️ Failed to update Flutter, but continuing..."
    fi
    cd - > /dev/null
  fi
  
  # Verify Flutter was installed
  if [ ! -f "$FLUTTER_INSTALL_DIR/bin/flutter" ]; then
    echo "❌ Flutter binary not found after installation"
    return 1
  fi
  
  export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH"
  echo "✅ Flutter installed at $FLUTTER_INSTALL_DIR"
  return 0
}

# Check if Flutter is available
if ! command -v flutter >/dev/null 2>&1; then
  echo "⚠️ Flutter not found in PATH, attempting to find or install..."
  
  # Try to find Flutter in common locations
  if [ -d "/usr/local/flutter" ] && [ -f "/usr/local/flutter/bin/flutter" ]; then
    export PATH="/usr/local/flutter/bin:$PATH"
    echo "✅ Found Flutter at /usr/local/flutter"
  elif [ -d "$HOME/flutter" ] && [ -f "$HOME/flutter/bin/flutter" ]; then
    export PATH="$HOME/flutter/bin:$PATH"
    echo "✅ Found Flutter at $HOME/flutter"
  elif command -v brew >/dev/null 2>&1; then
    echo "Homebrew found, checking if Flutter is installed via Homebrew..."
    if brew list flutter >/dev/null 2>&1; then
      echo "✅ Flutter found via Homebrew"
      # Flutter installed via Homebrew should already be in PATH
    else
      echo "Flutter not installed via Homebrew, attempting to install..."
      if brew install flutter; then
        echo "✅ Flutter installed via Homebrew"
      else
        echo "⚠️ Failed to install Flutter via Homebrew, trying manual installation..."
        if ! install_flutter; then
          echo "❌ Failed to install Flutter"
          exit 1
        fi
      fi
    fi
  else
    echo "Flutter not found in standard locations, attempting to install..."
    if ! install_flutter; then
      echo "❌ Failed to install Flutter automatically"
      echo ""
      echo "Xcode Cloud may not allow installing Flutter during the build."
      echo "Please use one of these alternatives:"
      echo "1. Use a custom Docker image with Flutter pre-installed (recommended)"
      echo "2. Configure Flutter in Xcode Cloud environment variables"
      echo "3. Ensure Flutter is available in PATH before this script runs"
      exit 1
    fi
  fi
fi

# Verify Flutter is now available
if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ Flutter still not available after installation attempt"
  echo ""
  echo "Debug information:"
  echo "PATH: $PATH"
  echo "HOME: $HOME"
  echo "Current directory: $(pwd)"
  echo ""
  echo "Checking common Flutter locations:"
  ls -la /usr/local/flutter/bin/flutter 2>/dev/null || echo "  /usr/local/flutter/bin/flutter: not found"
  ls -la "$HOME/flutter/bin/flutter" 2>/dev/null || echo "  $HOME/flutter/bin/flutter: not found"
  echo ""
  echo "For Xcode Cloud, you may need to:"
  echo "1. Use a custom Docker image with Flutter pre-installed"
  echo "2. Configure Flutter installation in Xcode Cloud environment variables"
  exit 1
fi

echo "✅ Flutter found: $(which flutter)"
flutter --version

# Get Flutter dependencies
echo "📦 Running flutter pub get..."
if ! flutter pub get; then
  echo "❌ flutter pub get failed"
  exit 1
fi

# Generate Flutter files needed for iOS build
echo "🔧 Generating Flutter iOS files..."
flutter precache --ios || echo "⚠️ flutter precache --ios failed (non-critical)"

# Navigate to iOS directory
if [ ! -d "ios" ]; then
  echo "❌ ios directory not found in $(pwd)"
  exit 1
fi

cd ios
echo "Changed to ios directory: $(pwd)"

# Install CocoaPods dependencies
echo "📦 Running pod install..."
if ! command -v pod >/dev/null 2>&1; then
  echo "⚠️ CocoaPods not found in PATH"
  # Try using bundler if Gemfile exists
  if [ -f "Gemfile" ]; then
    echo "Using Bundler for CocoaPods..."
    bundle install || echo "⚠️ bundle install failed"
    bundle exec pod install --repo-update
  else
    echo "❌ CocoaPods not available and no Gemfile found"
    echo "Xcode Cloud should have CocoaPods pre-installed"
    echo "PATH: $PATH"
    exit 1
  fi
else
  if ! pod install --repo-update; then
    echo "❌ pod install failed"
    exit 1
  fi
fi

echo "✅ Pre-build script completed successfully!"
