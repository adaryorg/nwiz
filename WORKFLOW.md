# Git Workflow for nwiz

This document describes the branching strategy and release process for the nwiz project.

## Branch Structure

```
feature branches -----> main -----> releases (tags)
      │                   │              │
      │                   │              └── Official releases triggered by tags
      │                   └── Stable, tested code
      └── Feature development
```

### Branches

- **`main`**: Primary stable branch  
  - All tested and approved code lives here
  - Receives code via pull requests from feature branches
  - Should always be in a deployable state
  - Releases are triggered by pushing tags to this branch

- **Feature branches**: Individual development branches
  - Created from `main` for each new feature or bugfix
  - Naming convention: `feature/description`, `bugfix/description`, `hotfix/description`
  - Merged back to `main` via pull requests when complete

## Development Workflow

### 1. Creating a Feature Branch
```bash
# Start from main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/new-feature-name

# Make your changes
# ... development work ...

# Commit and push feature branch
git add .
git commit -m "Add new feature description"
git push origin feature/new-feature-name
```

### 2. Creating Pull Request
```bash
# Create pull request: feature branch → main
gh pr create --base main --head feature/new-feature-name --title "Add new feature"
```

**Process**:
- Create PR from feature branch to `main`
- Review changes thoroughly
- Ensure all CI checks pass
- Merge the PR
- Delete feature branch after merge

### 3. Creating a Release
When main is ready for an official release:

```bash
# Ensure you're on main and up to date
git checkout main
git pull origin main

# Create and push version tag
git tag v0.0.4 -m "Release version 0.0.4"
git push origin v0.0.4
```

**Process**:
- Tag the main branch with semantic version
- Push the tag to GitHub
- This automatically triggers a GitHub release via Actions

## GitHub Actions

### Build and Test Workflow (`.github/workflows/build.yml`)
- **Triggers**: Push to `main`, PRs to `main`
- **Purpose**: Continuous integration and testing
- **Outputs**: Build artifacts for testing

### Release Workflow (`.github/workflows/release.yml`)
- **Triggers**: Push of version tags (e.g., `v*`)
- **Purpose**: Create official GitHub releases
- **Outputs**: GitHub release with downloadable binary

## Branch Protection Rules (Recommended)

Configure these settings in GitHub → Settings → Branches:

### Main Branch Protection
- Require pull request reviews before merging
- Require status checks to pass before merging
- Require branches to be up to date before merging
- Include administrators in restrictions
- Dismiss stale reviews when new commits are pushed

## Release Process

### Standard Release
1. Ensure `main` branch is stable and tested
2. Create version tag from main:
   ```bash
   git checkout main
   git pull origin main
   git tag v0.0.4 -m "Release version 0.0.4"
   git push origin v0.0.4
   ```
3. GitHub automatically creates the release via Actions

### Hotfix Process
For urgent fixes to released code:

1. Create hotfix branch from `main`:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b hotfix/critical-fix
   ```

2. Make the minimal necessary changes
3. Test thoroughly
4. Create PR: `hotfix/critical-fix` → `main`
5. After merging, create new patch release tag:
   ```bash
   git checkout main
   git pull origin main
   git tag v0.0.5 -m "Hotfix release 0.0.5"
   git push origin v0.0.5
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

- **Development**: PRs to `main` run full test suite
- **Release**: Version tags pushed to `main` create GitHub releases
- **Artifacts**: All builds create downloadable binaries

## Quick Reference

```bash
# Start new feature
git checkout main
git pull origin main
git checkout -b feature/my-feature

# Create pull request when ready
gh pr create --base main --head feature/my-feature

# Create release
git checkout main
git pull origin main
git tag v0.0.4 -m "Release v0.0.4"
git push origin v0.0.4
```

## Best Practices

1. **Feature branches should be short-lived** - merge frequently to avoid conflicts
2. **Write descriptive commit messages** - helps with release notes and debugging
3. **Test thoroughly** - ensure CI passes before merging
4. **Keep main stable** - it should always be deployable
5. **Use semantic versioning** - makes it clear what type of changes are included
6. **Delete merged feature branches** - keeps the repository clean

This simplified workflow reduces complexity while maintaining code quality and providing a clear path from development to release.