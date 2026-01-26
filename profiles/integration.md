# Profile Integration Guide

This document describes how to add `--profile` support to `hcloud-provision.sh`.

## Changes Required

### 1. Add configuration variable (line ~45)

```bash
# Profile configuration
SERVER_PROFILE="${SERVER_PROFILE:-dev}"  # dev, nyx, full
```

### 2. Add to usage() function (line ~93)

```bash
    --profile PROFILE   Installation profile: dev, nyx, full (default: dev)
```

### 3. Add to argument parsing (line ~237)

```bash
    --profile)
        SERVER_PROFILE="$2"
        shift 2
        ;;
```

### 4. Add profile execution after bootstrap (line ~550, after bootstrap-dev-server.sh runs)

```bash
# Run profile-specific setup
run_profile() {
    local profile="$1"
    local server_ip="$2"
    
    case "${profile}" in
        dev)
            log_info "Using default dev profile (no additional setup)"
            ;;
        nyx)
            log_step "Running Nyx profile"
            ssh -o StrictHostKeyChecking=accept-new -p "${SSH_PORT}" "${SSH_USER}@${server_ip}" \
                "curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/profiles/nyx.sh | sudo bash"
            ;;
        full)
            log_step "Running full profile (dev + nyx)"
            ssh -o StrictHostKeyChecking=accept-new -p "${SSH_PORT}" "${SSH_USER}@${server_ip}" \
                "curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/profiles/nyx.sh | sudo bash"
            ;;
        *)
            log_warn "Unknown profile: ${profile}, skipping"
            ;;
    esac
}

# Call after main bootstrap completes
run_profile "${SERVER_PROFILE}" "${SERVER_IP}"
```

### 5. Update examples in usage

```bash
Examples:
    # Create Nyx AI assistant server
    ./hcloud-provision.sh --name nyx --profile nyx --type cx23

    # Create full dev + assistant server
    ./hcloud-provision.sh --name fullstack --profile full
```

## Quick Patch

For now, you can run profiles manually after provisioning:

```bash
# Provision base server
./hcloud-provision.sh --name nyx --type cx23

# Then SSH in and run profile
ssh nyx
curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/profiles/nyx.sh | sudo bash
```

Or as one-liner:

```bash
./hcloud-provision.sh --name nyx --type cx23 && \
  ssh nyx 'curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/profiles/nyx.sh | sudo bash'
```
