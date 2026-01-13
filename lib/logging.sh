#!/usr/bin/env bash
# ABOUTME: Shared logging library with timestamps and log files
# ABOUTME: Used by bootstrap-dev-server.sh, hcloud-provision.sh, and other scripts
#
# Usage:
#   source lib/logging.sh
#   init_logging "script-name"    # Initialize logging (creates log file)
#   log_info "message"            # Info level
#   log_ok "message"              # Success message
#   log_warn "message"            # Warning message (to stderr)
#   log_error "message"           # Error message (to stderr)
#   log_step "message"            # Major step marker
#   log_phase "phase name"        # Phase marker
#   log_debug "message"           # Debug (only if LOG_LEVEL=DEBUG)
#   log_timer_start "name"        # Start timing
#   log_timer_end "name"          # End timing and print duration

# =============================================================================
# Configuration
# =============================================================================

# Log level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Log file path (set by init_logging)
LOG_FILE="${LOG_FILE:-}"

# Log directory
LOG_DIR="${LOG_DIR:-${HOME}/.local/log/bootstrap}"

# Colors for output (can be disabled with NO_COLOR=1)
if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Timer storage (associative array)
declare -A LOG_TIMERS

# =============================================================================
# Initialization
# =============================================================================

# Initialize logging with optional script name
# Creates log directory and log file
init_logging() {
    local script_name="${1:-bootstrap}"
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')

    # Create log directory
    mkdir -p "${LOG_DIR}"

    # Set log file path
    LOG_FILE="${LOG_DIR}/${script_name}-${timestamp}.log"

    # Write initial log entry
    {
        echo "=========================================="
        echo "Log started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script: ${script_name}"
        echo "User: $(whoami)"
        echo "Host: $(hostname)"
        echo "PWD: $(pwd)"
        echo "=========================================="
        echo ""
    } >> "${LOG_FILE}"

    log_debug "Logging initialized: ${LOG_FILE}"
}

# =============================================================================
# Log Level Check
# =============================================================================

# Check if a log level should be output based on current LOG_LEVEL
should_log() {
    local level="$1"

    case "${LOG_LEVEL}" in
        DEBUG)
            return 0
            ;;
        INFO)
            [[ "${level}" != "DEBUG" ]]
            ;;
        WARN)
            [[ "${level}" == "WARN" || "${level}" == "ERROR" ]]
            ;;
        ERROR)
            [[ "${level}" == "ERROR" ]]
            ;;
        *)
            return 0
            ;;
    esac
}

# =============================================================================
# Core Logging Functions
# =============================================================================

# Internal: Write to log file if enabled
write_to_log() {
    local message="$1"
    if [[ -n "${LOG_FILE}" && -w "$(dirname "${LOG_FILE}")" ]]; then
        echo "${message}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

# Internal: Format and output log message
log_message() {
    local level="$1"
    local color="$2"
    local message="$3"
    local to_stderr="${4:-false}"

    # Skip if log level doesn't match
    if ! should_log "${level}"; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local formatted_console="${timestamp} ${color}[${level}]${NC} ${message}"
    local formatted_file="${timestamp} [${level}] ${message}"

    # Write to console
    if [[ "${to_stderr}" == "true" ]]; then
        echo -e "${formatted_console}" >&2
    else
        echo -e "${formatted_console}"
    fi

    # Write to log file
    write_to_log "${formatted_file}"
}

# =============================================================================
# Public Logging Functions
# =============================================================================

# Info level message
log_info() {
    log_message "INFO" "${BLUE}" "$1"
}

# Success/OK message
log_ok() {
    log_message "OK" "${GREEN}" "$1"
}

# Warning message (to stderr)
log_warn() {
    log_message "WARN" "${YELLOW}" "$1" "true"
}

# Error message (to stderr)
log_error() {
    log_message "ERROR" "${RED}" "$1" "true"
}

# Step marker (for major steps)
log_step() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${timestamp} ${CYAN}[STEP]${NC}  ═══ ${message} ═══"
    write_to_log "${timestamp} [STEP] ═══ ${message} ═══"
}

# Phase marker
log_phase() {
    log_step "Phase: $1"
}

# Debug message (only if LOG_LEVEL=DEBUG)
log_debug() {
    if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
        log_message "DEBUG" "${NC}" "$1"
    fi
}

# =============================================================================
# Timer Functions
# =============================================================================

# Start a named timer
log_timer_start() {
    local name="$1"
    LOG_TIMERS["${name}"]=$(date +%s)
    log_debug "Timer started: ${name}"
}

# End a named timer and log duration
log_timer_end() {
    local name="$1"
    local start_time="${LOG_TIMERS[${name}]:-}"

    if [[ -z "${start_time}" ]]; then
        log_warn "Timer '${name}' was not started"
        return 1
    fi

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    if [[ ${minutes} -gt 0 ]]; then
        log_info "Timer '${name}': ${minutes}m ${seconds}s"
    else
        log_info "Timer '${name}': ${seconds}s"
    fi

    # Clean up
    unset "LOG_TIMERS[${name}]"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Print a horizontal line
log_line() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "${width}" '' | tr ' ' "${char}"
}

# Print a boxed message
log_box() {
    local message="$1"
    local width=$((${#message} + 4))

    log_line "═" "${width}"
    echo "║ ${message} ║"
    log_line "═" "${width}"
}

# Get current log file path
get_log_file() {
    echo "${LOG_FILE}"
}

# Tail the current log file
tail_log() {
    local lines="${1:-20}"
    if [[ -f "${LOG_FILE}" ]]; then
        tail -n "${lines}" "${LOG_FILE}"
    else
        echo "No log file available"
    fi
}

# =============================================================================
# Export Functions
# =============================================================================

# Export all functions for use in subshells
export -f log_info log_ok log_warn log_error log_step log_phase log_debug
export -f log_timer_start log_timer_end
export -f log_line log_box get_log_file tail_log
export -f init_logging should_log write_to_log log_message
