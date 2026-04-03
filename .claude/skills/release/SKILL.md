# Release Skill

Automate the release process with validation checks.

## Procedure

### 1. Pre-release Checks
- Verify working tree is clean: `git status`
- Verify all tests pass
  - Lambda: `python3 -m pytest test_handler.py -v` (각 함수)
  - SDK: `cd sdk && npm test`
  - Simulator: `cd simulator && npm test`
- Check for uncommitted changes
- Verify Terraform is valid: `cd terraform && terraform validate`

### 2. Determine Version
- Review changes since last tag: `git log $(git describe --tags --abbrev=0)..HEAD --oneline`
- Apply semver rules:
  - MAJOR: Breaking API changes (SDK API, Lambda event schema)
  - MINOR: New features, backward compatible
  - PATCH: Bug fixes only

### 3. Update Changelog
- Group changes by type (Added, Changed, Fixed, Removed)
- Include commit references
- Add date and version header

### 4. Create Release
- Update version in relevant files (`sdk/package.json`, `simulator/package.json`)
- Create git tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- Generate release notes

### 5. Summary
- Display version bump
- List key changes
- Show next steps (push tag, terraform apply, etc.)

## Usage
Run with `/release` command
