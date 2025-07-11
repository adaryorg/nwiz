# Git Workflow for Nocturne TUI

This document describes the branching strategy and release process for the Nocturne TUI project.

## Branch Structure

```
dev -----> main -----> release
 │           │           │
 │           │           └── Official releases and tags
 │           └── Stable, tested code
 └── Active development
```

### Branches

- **`dev`**: Active development branch
  - All feature development happens here
  - Continuous integration runs on every push
  - May contain experimental or unstable code

- **`main`**: Stable integration branch  
  - Code that has been tested and is ready for release
  - Only receives code via pull requests from `dev`
  - Should always be in a deployable state

- **`release`**: Production release branch
  - Contains only released versions
  - Receives code via pull requests from `main`
  - All official version tags are created here
  - Triggers automatic GitHub releases

## Development Workflow

### 1. Daily Development
```bash
# Work on the dev branch
git checkout dev
git pull origin dev

# Make your changes
# ... development work ...

# Commit and push to dev
git add .
git commit -m "Add new feature"
git push origin dev
```

### 2. Promoting Dev to Main
When dev is stable and ready for the next release:

```bash
# Create pull request: dev → main
gh pr create --base main --head dev --title "Merge dev to main for next release"
```

**Process**:
- Create PR from `dev` to `main`
- Review changes thoroughly
- Ensure all CI checks pass
- Merge the PR

### 3. Creating a Release
When main is ready for an official release:

```bash
# Create pull request: main → release
gh pr create --base release --head main --title "Release v0.0.4"
```

**Process**:
- Create PR from `main` to `release`
- Update version numbers if needed
- Create and push a version tag:
  ```bash
  git checkout release
  git tag v0.0.4
  git push origin v0.0.4
  ```
- Merge the PR
- This automatically triggers a GitHub release

## GitHub Actions

### Build and Test Workflow (`.github/workflows/build.yml`)
- **Triggers**: Push to `dev` or `main`, PRs to `main` or `release`
- **Purpose**: Continuous integration and testing
- **Outputs**: Build artifacts for testing

### Release Workflow (`.github/workflows/release.yml`)
- **Triggers**: Push to `release` branch or version tags
- **Purpose**: Create official GitHub releases
- **Outputs**: GitHub release with downloadable binary

## Branch Protection Rules (Recommended)

Configure these settings in GitHub → Settings → Branches:

### Main Branch Protection
- Require pull request reviews before merging
- Require status checks to pass before merging
- Require branches to be up to date before merging
- Include administrators in restrictions

### Release Branch Protection
- Require pull request reviews before merging
- Require status checks to pass before merging
- Restrict pushes to specific users/teams
- Include administrators in restrictions

## Release Process

### Manual Release
1. Ensure `main` branch is stable and tested
2. Create PR: `main` → `release`
3. Review and approve the PR
4. Create version tag:
   ```bash
   git checkout release
   git tag v0.0.4 -m "Release version 0.0.4"
   git push origin v0.0.4
   ```
5. Merge the PR
6. GitHub automatically creates the release

### Hotfix Process
For urgent fixes to released code:

1. Create hotfix branch from `release`:
   ```bash
   git checkout release
   git checkout -b hotfix/critical-fix
   ```

2. Make the minimal necessary changes
3. Test thoroughly
4. Create PR: `hotfix/critical-fix` → `release`
5. After merging, also merge back to `main` and `dev`:
   ```bash
   # Merge to main
   git checkout main
   git merge release
   git push origin main
   
   # Merge to dev
   git checkout dev
   git merge main
   git push origin dev
   ```

## Version Tagging

### Tag Format
- Use semantic versioning: `v<major>.<minor>.<patch>`
- Examples: `v0.0.4`, `v1.0.0`, `v1.2.3`

### Creating Tags
```bash
# Annotated tag (recommended)
git tag -a v0.0.4 -m "Release version 0.0.4"

# Push tag to trigger release
git push origin v0.0.4
```

## CI/CD Integration

- **Development**: Every push to `dev` runs tests
- **Integration**: PRs to `main` run full test suite
- **Release**: Pushes to `release` create GitHub releases
- **Artifacts**: All builds create downloadable binaries

## Quick Reference

```bash
# Start new development
git checkout dev
git pull origin dev

# Create feature branch (optional)
git checkout -b feature/new-feature

# Ready for main
gh pr create --base main --head dev

# Ready for release  
gh pr create --base release --head main

# Tag and release
git checkout release
git tag v0.0.4
git push origin v0.0.4
```

This workflow ensures code quality, proper testing, and controlled releases while maintaining a clear separation between development, integration, and production code.