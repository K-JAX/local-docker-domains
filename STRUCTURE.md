# Recommended Project Structure

## Current Issues to Address:
1. **`dependencies/` shouldn't contain empty dirs** - these are external tools
2. **Missing essential files** - LICENSE, CHANGELOG, VERSION
3. **`lib/` structure** could be cleaner
4. **Missing templates** for configurations
5. **No examples** for users to follow

## Recommended Structure:

```
local-docker-domains/
├── README.md                    # ✅ Excellent description
├── LICENSE                      # 📝 ADD - MIT license
├── CHANGELOG.md                 # 📝 ADD - Version history
├── VERSION                      # 📝 ADD - Current version (1.0.0)
├── Makefile                     # 📝 ADD - Install/uninstall commands
├── .gitignore                   # 📝 ADD - Standard ignores
│
├── bin/                         # ✅ Good - Executable scripts
│   ├── ldd                      # 🔄 RENAME - Main command (no .sh)
│   ├── ldd-setup               # 🔄 RENAME - Remove .sh
│   ├── ldd-reset               # 🔄 RENAME - Remove .sh  
│   └── ldd-proxy               # 🔄 RENAME - Remove .sh
│
├── lib/                         # ✅ Good structure
│   ├── common.sh               # 📝 ADD - Shared functions
│   ├── proxy/                  # 🔄 RENAME - Remove -resolver
│   │   ├── detector.sh         # 🔄 MOVE - proxy-detection.sh
│   │   ├── haproxy.sh          # 📝 ADD - HAProxy management
│   │   ├── nginx.sh            # 📝 ADD - nginx management
│   │   └── valet.sh            # 📝 ADD - Valet detection
│   ├── hosts/                  # 📝 ADD - Hosts management
│   │   ├── manager.sh          # 📝 ADD - hostctl wrapper
│   │   └── validator.sh        # 📝 ADD - Validation logic
│   ├── ssl/                    # 📝 ADD - SSL management
│   │   ├── mkcert.sh           # 📝 ADD - mkcert wrapper
│   │   └── validator.sh        # 📝 ADD - Cert validation
│   └── docker/                 # 🔄 RENAME - Remove -integration
│       ├── compose.sh          # 📝 ADD - Docker Compose helpers
│       └── env-parser.sh       # 📝 ADD - .env.local parsing
│
├── templates/                   # 📝 ADD - Configuration templates
│   ├── haproxy.cfg.template
│   ├── nginx.conf.template
│   ├── env.local.example
│   └── docker-compose.yml.example
│
├── examples/                    # 📝 ADD - Real-world examples
│   ├── sveltekit-wordpress/
│   │   ├── .env.local
│   │   ├── docker-compose.yml
│   │   └── README.md
│   ├── nextjs-api/
│   └── full-stack-js/
│
├── tests/                       # 📝 ADD - Testing (future)
│   ├── unit/
│   └── integration/
│
└── docs/                        # 📝 ADD - Documentation
    ├── installation.md
    ├── configuration.md
    ├── troubleshooting.md
    └── contributing.md
```

## Key Changes Needed:

### 1. Remove `.sh` extensions from bin files
- Makes commands cleaner: `ldd setup` vs `ldd-setup.sh`
- Standard practice for CLI tools

### 2. Remove empty `dependencies/` directory
- These are external tools (brew install, not part of your repo)
- Document dependencies in README instead

### 3. Add essential project files
- LICENSE (MIT recommended)
- VERSION file for releases
- CHANGELOG.md for version history
- .gitignore for standard ignores

### 4. Reorganize lib/ structure
- Flatten some directories (`proxy-resolver/` → `proxy/`)
- Add missing components (hosts, ssl, docker)
- Create shared `common.sh` for utilities

### 5. Add templates/ directory
- Users need examples of configuration files
- Makes it easier to get started

### 6. Add examples/ directory
- Real-world usage examples
- Show different stack configurations

## Migration Commands:

```bash
# Remove empty dependency dirs
rm -rf dependencies/

# Rename bin files (remove .sh)
mv bin/ldd-setup.sh bin/ldd-setup
mv bin/reset.sh bin/ldd-reset
mv bin/haproxy-control.sh bin/ldd-proxy

# Reorganize lib
mv lib/proxy-resolver lib/proxy
mv lib/proxy/proxy-detection.sh lib/proxy/detector.sh
mv lib/docker-integration lib/docker

# Create missing directories
mkdir -p templates examples docs tests/{unit,integration}
mkdir -p lib/{hosts,ssl}

# Add executable permissions
chmod +x bin/*
```

---

## Code Migration Strategy

### **lib/ Structure & Contents**

#### **lib/proxy-resolver/** → **lib/proxy/**
*Smart proxy detection and conflict resolution*

```bash
lib/proxy/
├── detector.sh              # Main detection logic (from proxy-detection.sh)
├── conflict-resolver.sh     # Port conflict resolution strategies  
├── valet-handler.sh         # Laravel Valet detection & integration
├── mamp-handler.sh          # MAMP/XAMPP detection
├── nginx-handler.sh         # Existing nginx detection
├── apache-handler.sh        # Existing Apache detection
└── fallback-strategy.sh     # HAProxy → nginx → manual fallback
```

**Functions:**
- `detect_existing_proxies()` - Your smart detection logic
- `check_port_conflicts()` - Port 80/443 availability
- `resolve_proxy_strategy()` - Choose best proxy approach
- `setup_haproxy_with_conflicts()` - HAProxy on alternate ports
- `setup_nginx_fallback()` - nginx fallback configuration

#### **lib/docker-integration/** → **lib/docker/**
*Docker Compose and .env.local integration*

```bash
lib/docker/
├── env-parser.sh            # Parse .env.local for domains
├── compose-helper.sh        # Docker Compose utilities
├── domain-mapper.sh         # Map env vars to domains
├── traefik-config.sh        # Traefik label generation
└── container-manager.sh     # Container lifecycle management
```

**Functions:**
- `get_all_domains()` - Your existing domain discovery
- `parse_env_local()` - Extract PROJECT_TITLE, domains, etc.
- `generate_traefik_labels()` - Dynamic Traefik configuration
- `validate_compose_file()` - Ensure Docker Compose compatibility
- `setup_docker_networks()` - Network configuration

#### **lib/orchestrator/** (New)
*Main workflow coordination and user experience*

```bash
lib/orchestrator/
├── setup-workflow.sh       # Main setup orchestration
├── reset-workflow.sh       # Main reset orchestration  
├── validation.sh           # End-to-end validation
├── user-interaction.sh     # Prompts, confirmations, help
└── status-reporter.sh      # Status reporting and diagnostics
```

**Functions:**
- `main_setup_workflow()` - Coordinates entire setup process
- `main_reset_workflow()` - Coordinates cleanup process
- `validate_environment()` - Pre-flight checks
- `report_setup_status()` - Show user what was configured
- `interactive_conflict_resolution()` - User prompts for conflicts

#### **lib/common.sh** (New)
*Shared functions used across all modules*

**Functions:**
- `log_info()`, `log_error()`, `log_success()` - Consistent logging
- `require_sudo()` - Sudo requirement handling
- `check_command_exists()` - Command availability checks
- `get_os_type()` - OS detection (macOS, Linux, etc.)
- `cleanup_on_exit()` - Graceful cleanup on script exit

### **How They Work Together**

#### **Setup Flow:**
```bash
# bin/ldd-setup calls:
orchestrator/setup-workflow.sh
  ├── docker/env-parser.sh              # Parse .env.local
  ├── proxy/detector.sh                 # Detect conflicts
  ├── proxy/conflict-resolver.sh        # Choose strategy
  ├── dependencies/*/install.sh         # Install tools
  ├── dependencies/*/wrapper.sh         # Configure tools
  └── orchestrator/validation.sh        # Validate setup
```

#### **Reset Flow:**
```bash
# bin/ldd-reset calls:
orchestrator/reset-workflow.sh
  ├── docker/container-manager.sh       # Stop containers
  ├── proxy/cleanup.sh                  # Clean proxy configs
  ├── dependencies/*/wrapper.sh         # Clean dependencies
  └── orchestrator/status-reporter.sh   # Report cleanup
```

### **Migration from Existing Scripts**

#### **proxy-detection.sh** → Split into:
- `lib/proxy/detector.sh` - Detection logic
- `lib/proxy/conflict-resolver.sh` - Resolution strategies
- `lib/proxy/*-handler.sh` - Specific proxy handlers

#### **setup.sh** → Split into:
- `lib/orchestrator/setup-workflow.sh` - Main flow
- `lib/docker/env-parser.sh` - Domain parsing
- Move proxy logic to `lib/proxy/`

#### **reset.sh** → Split into:
- `lib/orchestrator/reset-workflow.sh` - Main cleanup flow
- Keep proxy cleanup in `lib/proxy/`

#### **haproxy-control.sh** → Becomes:
- `dependencies/haproxy/wrapper.sh` - HAProxy management
- `lib/proxy/haproxy-handler.sh` - Integration logic

### **Benefits of This Structure**

1. **Modular** - Each component has clear responsibility
2. **Testable** - Can test each module independently  
3. **Reusable** - Other projects could use individual modules
4. **Maintainable** - Easy to find and fix specific functionality
5. **Extensible** - Easy to add new proxy types or features

---

## Architectural Framework & Inspirations

### **What Framework Is This?**

This architecture combines several well-established patterns:

#### **1. Modular Monolith Architecture**
- Single repository with clear module boundaries
- Each module (`lib/proxy/`, `lib/docker/`) has distinct responsibilities
- Modules communicate through well-defined interfaces
- Popular in: Enterprise applications, large codebases

#### **2. Command Pattern + Strategy Pattern**
- `bin/` scripts are Commands that orchestrate operations
- `lib/proxy/` uses Strategy pattern for different proxy types
- `dependencies/` are Adapters for external tools
- Popular in: CLI tools, automation frameworks

#### **3. Plugin Architecture**
- `dependencies/` folder acts like plugin system
- Each dependency is self-contained with install/wrapper/check
- Easy to add new dependencies without changing core
- Popular in: Build tools, package managers

### **Projects That Inspire This Architecture**

#### **Shell Script Ecosystems:**
1. **Oh My Zsh** - Plugin architecture with `plugins/`, `themes/`, `lib/`
2. **Homebrew** - Formula architecture with dependencies and taps
3. **Docker Buildx** - Plugin system with clear interfaces
4. **Terraform** - Provider architecture with modules

#### **Development Tool Projects:**
1. **Laravel Sail** - Docker orchestration with smart detection
2. **Rails** - Convention over configuration, clear file structure
3. **Vue CLI** - Plugin architecture for project setup
4. **Create React App** - Abstracted toolchain with escape hatches

#### **Unix Tool Philosophy:**
1. **Git** - Subcommands (`git-*`) with shared libraries
2. **Apache/nginx** - Modular configuration with includes
3. **Systemd** - Service orchestration with dependencies
4. **Package Managers** - Dependency resolution with repositories

### **Why This Architecture Works Well:**

#### **For Shell Scripts:**
- **Testability** - Each module can be tested independently
- **Maintainability** - Clear separation of concerns
- **Extensibility** - Easy to add new proxy types or dependencies
- **Discoverability** - Logical file organization

#### **For Development Tools:**
- **User Experience** - Simple commands hide complex orchestration
- **Flexibility** - Users can override specific components
- **Reliability** - Fallback strategies and conflict resolution
- **Cross-platform** - Abstracted dependencies

### **Academic Name:**
This is a **"Layered Plugin Architecture with Dependency Injection"**:
- **Layered**: `bin/` → `lib/` → `dependencies/`
- **Plugin**: Modular components with clear interfaces
- **Dependency Injection**: External tools abstracted through wrappers

**Most similar to:** Modern CLI tools like `kubectl`, `terraform`, `docker-compose` - they all use variations of this pattern for managing complex orchestration with external dependencies.


