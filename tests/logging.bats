#!/usr/bin/env bats
# ABOUTME: Tests for lib/logging.sh
# ABOUTME: Validates logging functions, timers, and log file creation

load 'test_helper'

setup() {
    common_setup
    export LOG_DIR="${TEST_TEMP_DIR}/logs"
    export NO_COLOR=1
    source "${PROJECT_ROOT}/lib/logging.sh"
}

teardown() {
    common_teardown
}

# =============================================================================
# init_logging Tests
# =============================================================================

@test "init_logging creates log directory" {
    init_logging "test-script"
    assert_dir_exists "${LOG_DIR}"
}

@test "init_logging creates log file" {
    init_logging "test-script"
    assert_file_exists "${LOG_FILE}"
}

@test "init_logging log file contains header" {
    init_logging "test-script"
    run cat "${LOG_FILE}"
    assert_contains "${output}" "Log started:"
    assert_contains "${output}" "Script: test-script"
}

@test "init_logging uses provided script name in filename" {
    init_logging "my-custom-script"
    assert_contains "${LOG_FILE}" "my-custom-script"
}

# =============================================================================
# log_info Tests
# =============================================================================

@test "log_info outputs message to stdout" {
    init_logging "test"
    run log_info "test message"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "test message"
    assert_contains "${output}" "[INFO]"
}

@test "log_info writes to log file" {
    init_logging "test"
    log_info "file test message"
    run cat "${LOG_FILE}"
    assert_contains "${output}" "file test message"
}

# =============================================================================
# log_ok Tests
# =============================================================================

@test "log_ok outputs success message" {
    init_logging "test"
    run log_ok "success message"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "success message"
    assert_contains "${output}" "[OK]"
}

# =============================================================================
# log_warn Tests
# =============================================================================

@test "log_warn outputs to stderr" {
    init_logging "test"
    run bash -c "source '${PROJECT_ROOT}/lib/logging.sh' && log_warn 'warning test' 2>&1"
    assert_contains "${output}" "warning test"
    assert_contains "${output}" "[WARN]"
}

# =============================================================================
# log_error Tests
# =============================================================================

@test "log_error outputs to stderr" {
    init_logging "test"
    run bash -c "source '${PROJECT_ROOT}/lib/logging.sh' && log_error 'error test' 2>&1"
    assert_contains "${output}" "error test"
    assert_contains "${output}" "[ERROR]"
}

# =============================================================================
# log_step Tests
# =============================================================================

@test "log_step outputs step marker" {
    init_logging "test"
    run log_step "Major Step"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "[STEP]"
    assert_contains "${output}" "Major Step"
}

# =============================================================================
# log_phase Tests
# =============================================================================

@test "log_phase outputs phase marker" {
    init_logging "test"
    run log_phase "Setup"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "Phase: Setup"
}

# =============================================================================
# log_debug Tests
# =============================================================================

@test "log_debug outputs nothing when LOG_LEVEL is INFO" {
    export LOG_LEVEL="INFO"
    init_logging "test"
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

@test "log_debug outputs message when LOG_LEVEL is DEBUG" {
    export LOG_LEVEL="DEBUG"
    init_logging "test"
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "debug message"
}

# =============================================================================
# should_log Tests
# =============================================================================

@test "should_log returns true for INFO when LOG_LEVEL is DEBUG" {
    export LOG_LEVEL="DEBUG"
    run should_log "INFO"
    [ "$status" -eq 0 ]
}

@test "should_log returns false for DEBUG when LOG_LEVEL is INFO" {
    export LOG_LEVEL="INFO"
    run should_log "DEBUG"
    [ "$status" -eq 1 ]
}

@test "should_log returns true for ERROR when LOG_LEVEL is WARN" {
    export LOG_LEVEL="WARN"
    run should_log "ERROR"
    [ "$status" -eq 0 ]
}

@test "should_log returns false for INFO when LOG_LEVEL is ERROR" {
    export LOG_LEVEL="ERROR"
    run should_log "INFO"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Timer Tests
# =============================================================================

@test "log_timer_start stores timer" {
    log_timer_start "test_timer"
    [ -n "${LOG_TIMERS[test_timer]}" ]
}

@test "log_timer_end warns when timer not started" {
    init_logging "test"
    run bash -c "source '${PROJECT_ROOT}/lib/logging.sh' && log_timer_end 'nonexistent' 2>&1"
    [ "$status" -eq 1 ]
    assert_contains "${output}" "not started"
}

@test "log_timer_end outputs duration" {
    init_logging "test"
    log_timer_start "quick_timer"
    sleep 1
    run log_timer_end "quick_timer"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "Timer 'quick_timer':"
}

# =============================================================================
# Utility Function Tests
# =============================================================================

@test "log_line outputs horizontal line" {
    run log_line "=" 20
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 20 ]
}

@test "log_line uses default character" {
    run log_line
    [ "$status" -eq 0 ]
    assert_contains "${output}" "-"
}

@test "get_log_file returns log file path" {
    init_logging "test"
    result=$(get_log_file)
    [ "${result}" = "${LOG_FILE}" ]
}

@test "tail_log outputs last lines" {
    init_logging "test"
    log_info "line 1"
    log_info "line 2"
    log_info "line 3"
    run tail_log 2
    [ "$status" -eq 0 ]
    assert_contains "${output}" "line 3"
}

@test "tail_log handles missing log file" {
    export LOG_FILE=""
    run tail_log
    [ "$status" -eq 0 ]
    assert_contains "${output}" "No log file available"
}

# =============================================================================
# Color Tests
# =============================================================================

@test "NO_COLOR disables color codes" {
    export NO_COLOR=1
    source "${PROJECT_ROOT}/lib/logging.sh"
    [ -z "${RED}" ]
    [ -z "${GREEN}" ]
    [ -z "${NC}" ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "logging handles empty message" {
    init_logging "test"
    run log_info ""
    [ "$status" -eq 0 ]
}

@test "logging handles special characters" {
    init_logging "test"
    run log_info "Special chars: \$HOME \"quotes\" 'single' & | ; \\"
    [ "$status" -eq 0 ]
}

@test "logging handles very long message" {
    init_logging "test"
    local long_msg
    long_msg=$(printf 'x%.0s' {1..1000})
    run log_info "${long_msg}"
    [ "$status" -eq 0 ]
}

@test "logging works without init_logging" {
    export LOG_FILE=""
    run log_info "no init message"
    [ "$status" -eq 0 ]
    assert_contains "${output}" "no init message"
}
