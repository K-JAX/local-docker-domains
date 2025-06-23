# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure and architecture
- Smart proxy detection and conflict resolution
- Support for HAProxy, nginx, and Valet integration
- Docker Compose and .env.local integration
- SSL certificate management with mkcert
- Hosts file management with hostctl
- Modular architecture with clear separation of concerns

### Changed
- Nothing yet

### Deprecated
- Nothing yet

### Removed
- Nothing yet

### Fixed
- Nothing yet

### Security
- Nothing yet

## [0.1.0] - 2025-06-23

### Added
- Initial project setup
- Basic proxy detection logic
- Docker domain management foundation
- Project architecture documentation

---

## Changelog Maintenance Strategy

### **Auto-Generate from GitHub Releases (Chosen Approach)**

This changelog is automatically generated from GitHub release notes.

#### **Release Workflow:**

1. **Create GitHub Release** with detailed notes:
   ```markdown
   ## What's New in v1.1.0
   
   ### Added
   - Smart proxy detection for existing Valet/MAMP setups
   - Windows support via Chocolatey package manager
   
   ### Fixed  
   - HAProxy configuration now handles port conflicts gracefully
   - Setup script no longer fails when ports 80/443 are in use
   
   ### Migration Notes
   - If upgrading from 1.0.x, run `ldd reset --full` before setup
   ```

2. **Auto-generate changelog** using GitHub CLI:
   ```bash
   # Install GitHub CLI
   brew install gh
   
   # Generate changelog from releases
   gh release list --json tagName,name,body --limit 50 > releases.json
   # Use script to convert to CHANGELOG.md format
   ```

3. **Or use GitHub Actions** to auto-update this file:
   ```yaml
   # .github/workflows/changelog.yml
   name: Update Changelog
   on:
     release:
       types: [published]
   jobs:
     update-changelog:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v3
         - uses: rhysd/changelog-from-release/action@v3
           with:
             file: CHANGELOG.md
             github_token: ${{ secrets.GITHUB_TOKEN }}
   ```

#### **Benefits:**
- ✅ **Write once** - in GitHub releases  
- ✅ **Auto-sync** - changelog stays updated
- ✅ **Quality control** - manual release notes
- ✅ **Markdown compatible** - same format
- ✅ **Package manager friendly** - standard changelog format

#### **Manual Backup:**
If automation fails, just copy/paste from GitHub releases into this format:

```markdown
## [1.1.0] - 2025-07-15
<!-- Copy GitHub release notes here -->
```

### **Versioning Guidelines**

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes requiring user action
- **MINOR** (1.0.0 → 1.1.0): New features, backward compatible  
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, backward compatible
