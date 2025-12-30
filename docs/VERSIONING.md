# Versioning System

This repository uses an automated versioning system that increments the version number on every merge to the `main` or `master` branch.

## How It Works

### Version Storage
- The current version is stored in the `VERSION` file at the root of the repository
- The version follows semantic versioning format: `MAJOR.MINOR.PATCH` (e.g., `1.0.0`)

### Automatic Increment
- When a PR is merged to `main` or `master`, the GitHub Actions workflow `.github/workflows/version-increment.yml` automatically:
  1. Reads the current version from the `VERSION` file
  2. Increments the PATCH version by 1
  3. Updates the `VERSION` file
  4. Commits the change with message `chore: bump version to X.Y.Z [skip ci]`
  5. Creates and pushes a Git tag `vX.Y.Z`

### Version Display
The version is displayed in the application headers:

- **App Control Panel**: Shows version alongside the server IP address
  ```
  🧩 App Control Panel | 192.168.1.100 | v1.0.0
  ```

- **Server Control Panel**: Shows version alongside the server IP address
  ```
  🖥️ Server Control Panel | 192.168.1.100 | v1.0.0
  ```

## Implementation Details

### Files
- `VERSION` - Stores the current version number
- `lib/version.sh` - Contains version-related functions:
  - `get_app_version()` - Returns the raw version number
  - `format_version_display()` - Returns the formatted version (e.g., `v1.0.0`)
- `.github/workflows/version-increment.yml` - GitHub Actions workflow for auto-incrementing

### Testing
Unit tests for the versioning system are located in `test/version_tests.sh` and include:
- Version file existence check
- Version format validation (semantic versioning)
- Version reading functionality
- Version display formatting

Run version tests:
```bash
./test/version_tests.sh
```

## Manual Version Updates

If you need to manually update the version (e.g., for MAJOR or MINOR version bumps):

1. Edit the `VERSION` file directly
2. Commit the change
3. Create a tag manually if desired:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

Note: The automatic increment workflow will continue from your manually set version.

## Skip Version Increment

To prevent the workflow from running (e.g., for documentation-only changes), include `[skip ci]` in your commit message. However, note that merges to `main`/`master` will still trigger the workflow unless the merge commit itself contains `[skip ci]`.
