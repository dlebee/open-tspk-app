# Android CI/CD Setup

This document describes how to set up automated Android release builds and Play Store uploads using GitHub Actions.

## Overview

The workflow (`/.github/workflows/android-release.yml`) is a **manual workflow** that:
1. Clones the keystore repository (`open-tspk-app-ks`)
2. Builds a signed release AAB
3. Uploads it to Google Play Console

## Prerequisites

### 1. Keystore Repository

You need a separate private repository (`open-tspk-app-ks`) containing:
- The keystore file (`thygeson-app.keystore`)

Note: The `key.properties` file is created automatically from GitHub Secrets during the workflow run.

### 2. GitHub Secrets

Configure the following secrets in your GitHub repository settings (`Settings > Secrets and variables > Actions`):

#### Keystore Repository Access
- `KEYSTORE_REPO_TOKEN`: A GitHub Personal Access Token (PAT) with `repo` scope to download keystore files from the repository (`https://github.com/dlebee/open-tspk-app-ks`)
- `KEYSTORE_BRANCH`: (Optional) Branch name to download from (defaults to `main`)

#### Android Signing Credentials
- `ANDROID_STORE_PASSWORD`: The keystore password
- `ANDROID_KEY_PASSWORD`: The key password (optional, defaults to store password if not set)
- `ANDROID_KEY_ALIAS`: The key alias (defaults to `upload` if not set)
- `ANDROID_STORE_FILE`: The keystore filename (defaults to `thygeson-app.keystore` if not set)

#### Google Play Console (Workload Identity Federation)
- `WIF_PROVIDER`: Workload Identity Provider resource name (e.g., `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_NAME/providers/PROVIDER_NAME`)
- `WIF_SERVICE_ACCOUNT`: Service account email (e.g., `play-store-uploader@PROJECT_ID.iam.gserviceaccount.com`)

### 3. Google Play Service Account Setup (Workload Identity Federation)

**Why Workload Identity Federation?**
- ✅ **More Secure**: No long-lived service account keys stored in GitHub Secrets
- ✅ **Short-lived tokens**: Automatic credential rotation
- ✅ **Better audit trail**: Clear visibility of which repository/workflow accessed resources
- ✅ **Recommended by Google**: Best practice for CI/CD authentication

**Setup Steps:**

1. **Create a Google Cloud Project** (if you don't have one):
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select an existing one

2. **Enable Required APIs**:
   ```bash
   gcloud services enable \
     androidpublisher.googleapis.com \
     iamcredentials.googleapis.com \
     sts.googleapis.com
   ```

3. **Create a Service Account**:
   ```bash
   gcloud iam service-accounts create play-store-uploader \
     --display-name="Play Store Uploader" \
     --project=YOUR_PROJECT_ID
   ```

4. **Create Workload Identity Pool**:
   ```bash
   gcloud iam workload-identity-pools create github-actions-pool \
     --project=YOUR_PROJECT_ID \
     --location=global \
     --display-name="GitHub Actions Pool"
   ```

5. **Create Workload Identity Provider**:
   ```bash
   gcloud iam workload-identity-pools providers create-oidc github-provider \
     --project=YOUR_PROJECT_ID \
     --location=global \
     --workload-identity-pool=github-actions-pool \
     --display-name="GitHub Provider" \
     --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
     --attribute-condition="assertion.repository=='dlebee/open-tspk-app'" \
     --issuer-uri="https://token.actions.githubusercontent.com"
   ```
   
   **Note**: Replace `YOUR_GITHUB_USERNAME` with your actual GitHub username (e.g., `dlebee`). The attribute condition restricts access to your specific repository.

6. **Grant Service Account Access**:
   ```bash
   # Get your project number
   PROJECT_NUMBER=$(gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)")
   
   # Grant access (replace YOUR_GITHUB_USERNAME with your GitHub username)
   gcloud iam service-accounts add-iam-policy-binding \
     play-store-uploader@YOUR_PROJECT_ID.iam.gserviceaccount.com \
     --project=YOUR_PROJECT_ID \
     --role="roles/iam.workloadIdentityUser" \
     --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/YOUR_GITHUB_USERNAME/open-tspk-app"
   ```

7. **Link Service Account to Play Console**:
   - Go to [Google Play Console](https://play.google.com/console/)
   - Navigate to **Setup > API access**
   - Find your service account (`play-store-uploader@YOUR_PROJECT_ID.iam.gserviceaccount.com`)
   - Click **Grant access**
   - Grant permissions: **Release apps to production**, **Release apps to testing tracks**

8. **Set GitHub Secrets**:
   - `WIF_PROVIDER`: `projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider`
   - `WIF_SERVICE_ACCOUNT`: `play-store-uploader@YOUR_PROJECT_ID.iam.gserviceaccount.com`

**Note**: Replace placeholders (`YOUR_PROJECT_ID`, `YOUR_GITHUB_USERNAME`, etc.) with your actual values.

**Alternative: If the upload action doesn't support WIF credentials directly**

If `r0adkll/upload-google-play` doesn't work with Workload Identity Federation credentials, you can use the Play Store API directly via `gcloud`:

```yaml
- name: Upload to Play Store via gcloud
  run: |
    gcloud auth application-default print-access-token > /tmp/token.txt
    # Use the token with Play Store API or fastlane
```

Or use fastlane with the authenticated session.

## Usage

### Running the Workflow

1. Go to your repository on GitHub
2. Click on **Actions** tab
3. Select **Android Release Build & Upload** workflow
4. Click **Run workflow**
5. Choose the Play Store track:
   - `internal`: Internal testing track
   - `alpha`: Alpha testing track
   - `beta`: Beta testing track
   - `production`: Production release
6. Click **Run workflow**

The workflow will:
- Download the keystore file from the repository
- Build a signed release AAB
- Authenticate using Workload Identity Federation
- Upload it to the selected Play Store track

## Local Development

For local development, place the keystore repository at `../open-tspk-app-ks` relative to the project root. The build system will automatically detect and use it.

If the keystore is not found, the build will fall back to debug signing (useful for contributors who don't have access to the keystore).

## Troubleshooting

### Keystore Not Found
- Verify `KEYSTORE_REPO_TOKEN` has access to the repository (`https://github.com/dlebee/open-tspk-app-ks`)
- Check that the token has the `repo` scope
- Ensure `thygeson-app.keystore` exists in the repository
- Verify the branch name is correct (defaults to `main`, or set `KEYSTORE_BRANCH` secret)
- Ensure all required secrets are set: `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, etc.

### Build Fails with Signing Error
- Verify all Android signing secrets are set correctly
- Check that the keystore file exists and matches the filename in `key.properties`
- Ensure passwords are correct

### Play Store Upload Fails
- Verify `WIF_PROVIDER` and `WIF_SERVICE_ACCOUNT` secrets are set correctly
- Check that the Workload Identity Pool and Provider are configured correctly
- Ensure the service account has the correct permissions in Play Console
- Verify the repository path in the IAM policy binding matches your GitHub repository
- Check that the package name matches (`com.davidlebee.thygeson`)
- Review workflow logs for authentication errors
