# Xcode Cloud Configuration for Flutter

This project is configured to build on Xcode Cloud. The following files are required:

## Required Files

1. **`ios/.xcode.env`** - Tells Xcode where to find Flutter SDK
2. **`ios/ci_scripts/ci_pre_xcodebuild.sh`** - Pre-build script that sets up Flutter and CocoaPods

## How It Works

1. Xcode Cloud detects the `ci_scripts` directory
2. Before building, it runs `ci_pre_xcodebuild.sh`
3. The script:
   - Finds/installs Flutter SDK
   - Runs `flutter pub get` to get dependencies
   - Generates `ios/Flutter/Generated.xcconfig` (required for build)
   - Runs `pod install` to install CocoaPods dependencies
4. Xcode then builds the app using the generated files

## Important Notes

### Flutter SDK in Xcode Cloud

Xcode Cloud doesn't include Flutter by default. You have two options:

**Option 1: Install Flutter in the script** (slower but works)
- The script will attempt to download and install Flutter if not found
- This adds ~2-3 minutes to build time

**Option 2: Use a custom Docker image** (faster, recommended)
- Create a Docker image with Flutter pre-installed
- Configure Xcode Cloud to use this image
- See: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

### Troubleshooting

If you see errors about missing `Generated.xcconfig`:
- Ensure `flutter pub get` runs successfully
- Check that Flutter SDK is accessible
- Verify the script has execute permissions: `chmod +x ios/ci_scripts/ci_pre_xcodebuild.sh`

If CocoaPods errors occur:
- Xcode Cloud should have CocoaPods pre-installed
- If not, the script will attempt to install it (may require sudo access)

## Testing Locally

You can test the script locally:

```bash
cd ios
CI_WORKSPACE=.. ./ci_scripts/ci_pre_xcodebuild.sh
```

Then build in Xcode to verify everything works.
