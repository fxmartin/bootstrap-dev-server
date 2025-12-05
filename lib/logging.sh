#!/usr/bin/env bash
# ABOUTME: Professional logging library for bootstrap scripts
# ABOUTME: Provides timestamps, log levels, file output, and color support
#
# Usage:
#   source lib/logging.sh
#   init_logging "my-script"     # Initialize with script name for log file
#   log_info "Starting process"
#   log_ok "Task completed"
#   log_warn "Non-critical issue"
#   log_error "Something failed"
#   log_phase "Setup"            # Major phase marker
#   log_timer_start "build"      # Start timing an operation
#   log_timer_end "build"        # End timing and log duration
#
# Environment variables:
#   LOG_LEVEL      - DEBUG, INFO, WARN, ERROR (default: INFO)
#   LOG_FILE       - Path to log file (default: auto-created)
#   LOG_DIR        - Directory for log files (default: ~/.local/log/bootstrap)
#   LOG_TIMESTAMPS - true/false (default: true)
#   NO_COLOR       - Set to disable colors

# Prevent multiple sourcing
[[ -n "${_LOGGING_LOADED:-}" ]] && return 0
readonly _LOGGING_LOADED=1

# =============================================================================
# Configuration (overridable via environment)
# =============================================================================
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-}"
LOG_DIR="${LOG_DIR:-${HOME}/.local/log/bootstrap}"
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-true}"
NO_COLOR="${NO_COLOR:-}"

# =============================================================================
# ANSI Color Codes
# =============================================================================
if [[ -t 1 && -z "${NO_COLOR}" ]]; then
    readonly _LOG_RED='\033[0;31m'
    readonly _LOG_GREEN='\033[0;32m'
    readonly _LOG_YELLOW='\033[1;33m'
    readonly _LOG_BLUE='\033[0;34m'
    readonly _LOG_CYAN='\033[0;36m'
    readonly _LOG_GRAY='\033[0;90m'
    readonly _LOG_NC='\033[0m'
else
    readonly _LOG_RED=''
    readonly _LOG_GREEN=''
    readonly _LOG_YELLOW=''
    readonly _LOG_BLUE=''
    readonly _LOG_CYAN=''
    readonly _LOG_GRAY=''
    readonly _LOG_NC=''
fi

# =============================================================================
# Log Levels (numeric for comparison)
# =============================================================================
declare -A _LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [OK]=1
    [STEP]=1
    [WARN]=2
    [ERROR]=3
)

# =============================================================================
# State Variables
# =============================================================================
# shellcheck disable=SC2034  # LOG_PHASE is set for external use by scripts
LOG_PHASE=""
LOG_FUNCTION=""
declare -A _LOG_TIMERS=()

# =============================================================================
# Internal Functions
# =============================================================================

# Check if level should be logged based on LOG_LEVEL setting
# Uses ${array[key]+${array[key]}} pattern for set -u compatibility
_log_should_log() {
    local level="${1}"
    # Safe array access pattern that works with set -u
    local current_level="${_LOG_LEVELS[${LOG_LEVEL}]+${_LOG_LEVELS[${LOG_LEVEL}]}}"
    local msg_level="${_LOG_LEVELS[${level}]+${_LOG_LEVELS[${level}]}}"
    # Apply defaults if keys were not found
    current_level="${current_level:-1}"
    msg_level="${msg_level:-1}"
    [[ ${msg_level} -ge ${current_level} ]]
}

# Generate ISO-format timestamp
_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Route output to appropriate destination (stdout/stderr + optional file)
_log_output() {
    local level="${1}"
    local use_stderr="${2}"

    if [[ -n "${LOG_FILE}" ]]; then
        if [[ "${use_stderr}" == "true" ]]; then
            tee -a "${LOG_FILE}" >&2
        else
            tee -a "${LOG_FILE}"
        fi
    else
        if [[ "${use_stderr}" == "true" ]]; then
            cat >&2
        else
            cat
        fi
    fi
}

# Core logging function
_log() {
    local level="${1}"
    local color="${2}"
    local msg="${3}"
    local use_stderr="${4:-false}"
    local ts=""
    local output

    _log_should_log "${level}" || return 0

    [[ "${LOG_TIMESTAMPS}" == "true" ]] && ts="$(_log_timestamp) "

    # Format output based on terminal detection
    if [[ -t 1 && -z "${NO_COLOR}" ]]; then
        output=$(printf '%s%b[%-5s]%b %s\n' "${ts}" "${color}" "${level}" "${_LOG_NC}" "${msg}")
    else
        output=$(printf '%s%-5s %s\n' "${ts}" "${level}" "${msg}")
    fi

    echo "${output}" | _log_output "${level}" "${use_stderr}"
}

# =============================================================================
# Public API - Basic Logging
# =============================================================================

log_debug() {
    _log "DEBUG" "${_LOG_GRAY}" "${1}" "false"
}

log_info() {
    _log "INFO" "${_LOG_BLUE}" "${1}" "false"
}

log_ok() {
    _log "OK" "${_LOG_GREEN}" "${1}" "false"
}

log_warn() {
    _log "WARN" "${_LOG_YELLOW}" "${1}" "true"
}

log_error() {
    _log "ERROR" "${_LOG_RED}" "${1}" "true"
}

log_step() {
    _log "STEP" "${_LOG_CYAN}" "═══ ${1} ═══" "false"
}

log_fatal() {
    log_error "${1}"
    log_error "Fatal error - aborting script"
    exit "${2:-1}"
}

# =============================================================================
# Public API - Phase/Context Tracking
# =============================================================================

log_phase() {
    # shellcheck disable=SC2034  # LOG_PHASE is set for external use
    LOG_PHASE="${1}"
    log_step "Phase: ${1}"
}

log_enter() {
    LOG_FUNCTION="${FUNCNAME[1]}"
    log_debug "Entering ${LOG_FUNCTION}()"
}

log_exit() {
    local code="${1:-0}"
    log_debug "Exiting ${LOG_FUNCTION}() with code ${code}"
    LOG_FUNCTION=""
}

# =============================================================================
# Public API - Performance Timing
# =============================================================================

log_timer_start() {
    local name="${1}"
    # Use seconds since epoch with nanoseconds if available
    if date +%s.%N &>/dev/null; then
        _LOG_TIMERS[${name}]=$(date +%s.%N)
    else
        _LOG_TIMERS[${name}]=$(date +%s)
    fi
    log_debug "Timer '${name}' started"
}

log_timer_end() {
    local name="${1}"
    # Safe array access pattern that works with set -u
    local start="${_LOG_TIMERS[${name}]+${_LOG_TIMERS[${name}]}}"

    if [[ -z "${start}" ]]; then
        log_warn "Timer '${name}' was never started"
        return 1
    fi

    local end duration
    if date +%s.%N &>/dev/null; then
        end=$(date +%s.%N)
        # Use awk for floating point math (bc might not be available)
        duration=$(awk "BEGIN {printf \"%.2f\", ${end} - ${start}}")
    else
        end=$(date +%s)
        duration=$((end - start))
    fi

    log_info "${name} completed in ${duration}s"
    unset "_LOG_TIMERS[${name}]"
}

# =============================================================================
# Public API - Initialization & Management
# =============================================================================

init_logging() {
    local script_name="${1:-bootstrap}"
    local log_dir="${LOG_DIR:-${HOME}/.local/log/bootstrap}"

    # If user specified LOG_FILE, use it
    if [[ -n "${LOG_FILE}" ]]; then
        # Ensure parent directory exists
        mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
        log_debug "Using user-specified log file: ${LOG_FILE}"
        return 0
    fi

    # Auto-create log file in log directory
    if mkdir -p "${log_dir}" 2>/dev/null; then
        if [[ -w "${log_dir}" ]]; then
            LOG_FILE="${log_dir}/${script_name}-$(date +%Y%m%d-%H%M%S).log"
            log_info "Logging to: ${LOG_FILE}"
        else
            log_warn "Log directory not writable: ${log_dir}"
        fi
    else
        log_warn "Could not create log directory: ${log_dir}"
    fi
}

rotate_logs() {
    local log_dir="${LOG_DIR:-${HOME}/.local/log/bootstrap}"
    local keep="${1:-10}"

    [[ -d "${log_dir}" ]] || return 0

    # Find and delete old log files, keeping the most recent N
    # Use find instead of ls for better handling of special filenames
    local log_count
    # shellcheck disable=SC2312  # Pipeline is intentional, errors are acceptable
    log_count=$(find "${log_dir}" -maxdepth 1 -name "*.log" -type f 2>/dev/null | wc -l || echo 0)

    if [[ ${log_count} -gt ${keep} ]]; then
        local to_delete=$((log_count - keep))
        log_debug "Rotating logs: removing ${to_delete} old log file(s)"
        # Sort by modification time, oldest first, delete excess
        # shellcheck disable=SC2312  # Pipeline is intentional for log rotation
        find "${log_dir}" -maxdepth 1 -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null |
            sort -n |
            head -n "${to_delete}" |
            cut -d' ' -f2- |
            xargs -r rm -f || true
    fi
}

# =============================================================================
# Compatibility Aliases (for gradual migration)
# =============================================================================

# These match the old function signatures exactly
# Can be removed once migration is complete
# shellcheck disable=SC2034  # These are used by scripts that source this library
RED="${_LOG_RED}"
# shellcheck disable=SC2034
GREEN="${_LOG_GREEN}"
# shellcheck disable=SC2034
YELLOW="${_LOG_YELLOW}"
# shellcheck disable=SC2034
BLUE="${_LOG_BLUE}"
# shellcheck disable=SC2034
CYAN="${_LOG_CYAN}"
# shellcheck disable=SC2034
NC="${_LOG_NC}"
