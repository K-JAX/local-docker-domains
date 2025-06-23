# Main setup orchestration

#example flow for this file's calls


# bin/ldd-setup calls:
#orchestrator/setup-workflow.sh
#  ├── docker-integration/env-parser.sh      # Parse .env.local
#  ├── proxy-resolver/detector.sh            # Detect conflicts
#  ├── proxy-resolver/conflict-resolver.sh   # Choose strategy
#  ├── dependencies/*/install.sh             # Install tools
#  ├── dependencies/*/wrapper.sh             # Configure tools
#  └── orchestrator/validation.sh            # Validate setup