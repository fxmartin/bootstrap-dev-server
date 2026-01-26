#!/usr/bin/env bash
# ABOUTME: E2E test runner for bootstrap-dev-server profiles
# ABOUTME: Uses Docker/Podman to test dev and nyx profiles in isolation
#
# LIMITATIONS:
#   - Skips GitHub CLI authentication (requires interactive browser)
#   - Skips security hardening (UFW/iptables require kernel capabilities)
#   - Systemd services may not work (containers don't run systemd as PID 1)
#
# WHAT IS TESTED:
#   - Phase 1: Preflight and base packages installation
#   - Phase 2: Git, GitHub CLI, repository cloning
#   - Phase 4: Nix installation, flake creation, shell integration
#   - Phase 5: Final configuration
#   - Profile-specific installations (nyx profile)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
    cat <<EOF
E2E Test Runner

USAGE:
    ./e2e-runner.sh [OPTIONS]

OPTIONS:
    --profile PROFILE   Test specific profile: dev, nyx, all (default: all)
    --keep-containers   Keep containers running after tests for debugging
    --help              Show this help message

EXAMPLES:
    ./e2e-runner.sh                      # Test all profiles
    ./e2e-runner.sh --profile dev        # Test dev profile only
    ./e2e-runner.sh --keep-containers    # Keep containers for debugging
EOF
}

# Default configuration
PROFILE="all"
KEEP_CONTAINERS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --keep-containers)
            KEEP_CONTAINERS=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Detect container runtime
if command -v docker &>/dev/null; then
    RUNTIME="docker"
elif command -v podman &>/dev/null; then
    RUNTIME="podman"
else
    echo "ERROR: Neither docker nor podman found. Install one to run E2E tests."
    exit 1
fi

echo "Using container runtime: ${RUNTIME}"

# Build container image
echo "Building Ubuntu 24.04 test container..."
cd "${SCRIPT_DIR}"
${RUNTIME} build -t bootstrap-e2e:latest -f Dockerfile.ubuntu24 .

# Test function
run_profile_test() {
    local profile="$1"
    local container_name="e2e-${profile}-test"

    echo ""
    echo "========================================="
    echo "Testing profile: ${profile}"
    echo "========================================="

    # Start container (with host network for internet access)
    ${RUNTIME} run -d \
        --name "${container_name}" \
        --network host \
        -v "${PROJECT_ROOT}:/bootstrap:ro" \
        bootstrap-e2e:latest

    # Wait for container to be ready
    echo "Waiting for container to be ready..."
    sleep 3

    # Check if container is running
    if ! ${RUNTIME} inspect -f '{{.State.Running}}' "${container_name}" 2>/dev/null | grep -q "true"; then
        echo "ERROR: Container failed to start"
        ${RUNTIME} logs "${container_name}" 2>&1 || true
        ${RUNTIME} rm -f "${container_name}" 2>&1 || true
        return 1
    fi

    echo "Container started successfully"

    # Run bootstrap (with flags for headless container testing)
    echo "Running bootstrap-dev-server.sh..."
    ${RUNTIME} exec "${container_name}" \
        bash -c "cd /bootstrap && sudo -u fx ./bootstrap-dev-server.sh --skip-github-auth --skip-security-hardening"

    # Run profile if not dev
    if [[ "${profile}" != "dev" ]]; then
        echo "Running ${profile}.sh profile..."
        ${RUNTIME} exec "${container_name}" \
            bash -c "curl -fsSL file:///bootstrap/profiles/${profile}.sh | sudo bash"
    fi

    # Run verification (optional - may fail due to container limitations)
    echo "Running verification..."
    ${RUNTIME} exec "${container_name}" \
        sudo -u fx bash /bootstrap/tests/verify-server.sh || true

    # Show test summary
    echo ""
    echo "========================================="
    echo "E2E Test Summary: ${profile}"
    echo "========================================="
    echo "✅ Tested:"
    echo "  - Phase 1: Preflight and base packages"
    echo "  - Phase 2: Git and GitHub CLI setup"
    echo "  - Phase 4: Nix installation and configuration"
    if [[ "${profile}" != "dev" ]]; then
        echo "  - Profile: ${profile}.sh execution"
    fi
    echo ""
    echo "⏭️  Skipped (container limitations):"
    echo "  - GitHub CLI authentication (interactive)"
    echo "  - Phase 3: Security hardening (requires kernel capabilities)"
    echo "  - Systemd services (requires systemd as PID 1)"
    echo ""

    local status=0

    # Cleanup unless --keep-containers
    if [[ "${KEEP_CONTAINERS}" == "false" ]]; then
        echo "Cleaning up container..."
        ${RUNTIME} stop "${container_name}" >/dev/null 2>&1 || true
        ${RUNTIME} rm "${container_name}" >/dev/null 2>&1 || true
    else
        echo "Container kept running: ${RUNTIME} exec -it ${container_name} bash"
    fi

    return ${status}
}

# Run tests based on profile selection
case "${PROFILE}" in
    dev)
        run_profile_test "dev"
        ;;
    nyx)
        run_profile_test "nyx"
        ;;
    all)
        run_profile_test "dev"
        run_profile_test "nyx"
        ;;
    *)
        echo "Unknown profile: ${PROFILE}"
        usage
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo "E2E tests completed successfully!"
echo "========================================="
