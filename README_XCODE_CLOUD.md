# Xcode Cloud Configuration for Flutter

This project is configured to build on Xcode Cloud. The following files are required:

## Required Files

1. **`ios/.xcode.env`** - Tells Xcode where to find Flutter SDK
2. **`ios/ci_scripts/ci_post_clone.sh`** - Post-clone script that sets up Flutter and CocoaPods (runs after repository is cloned)

## How It Works

1. Xcode Cloud clones your repository
2. After cloning, it runs `ci_post_clone.sh` from the `ci_scripts` directory
3. The script:
   - Installs Flutter SDK if not available
   - Runs `flutter precache --ios` to download iOS tools
   - Runs `flutter pub get` to get dependencies
   - Installs CocoaPods via Homebrew
   - Runs `pod install` to install CocoaPods dependencies
4. Xcode then builds the app using the generated files

**Note:** The script uses `$CI_PRIMARY_REPOSITORY_PATH` which is automatically set by Xcode Cloud to point to your repository root.

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
- Verify the script has execute permissions: `chmod +x ios/ci_scripts/ci_post_clone.sh`

If CocoaPods errors occur:
- Xcode Cloud should have CocoaPods pre-installed
- If not, the script will attempt to install it (may require sudo access)

## Testing Locally

You can test the script locally:

```bash
cd ios
CI_PRIMARY_REPOSITORY_PATH=.. ./ci_scripts/ci_post_clone.sh
```

Then build in Xcode to verify everything works.
