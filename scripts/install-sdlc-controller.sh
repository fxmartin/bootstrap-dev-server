#!/usr/bin/env bash
# ABOUTME: Installs the sdlc controller with uv from a tag pinned in config/versions.env
# ABOUTME: Runs on a uv-managed Python (never /nix/store); same tag is a no-op, a new tag upgrades
#
# claude-code-config is public on GitHub, so no token is needed. The controller
# drives `sdlc fix` / `sdlc build` against the local GitLab (GITLAB_HOST).
#
# Idempotent: the installed tag is recorded in a state file, so a re-run with
# the same tag touches nothing and a bumped tag reinstalls. Paths are
# env-overridable so tests/sdlc-controller.bats can run it against a stub uv.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
LIB_PATH="${REPO_DIR}/lib/logging.sh"

if [[ -f "${LIB_PATH}" ]]; then
    # shellcheck source=../lib/logging.sh
    source "${LIB_PATH}"
else
    # shellcheck disable=SC2312
    log_info() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  ${1}"; }
    # shellcheck disable=SC2312
    log_ok() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [OK]    ${1}"; }
    # shellcheck disable=SC2312
    log_error() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${1}" >&2; }
fi

VERSIONS_FILE="${SDLC_VERSIONS_FILE:-${REPO_DIR}/config/versions.env}"
STATE_FILE="${SDLC_STATE_FILE:-${XDG_STATE_HOME:-${HOME}/.local/state}/bootstrap-dev-server/sdlc-controller.tag}"
CONTROLLER_REPO="git+https://github.com/fxmartin/claude-code-config"

# uv comes from the dev-env profile; make it findable outside a login shell.
export PATH="${HOME}/.nix-profile/bin:${HOME}/.local/bin:${PATH}"

if [[ ! -f "${VERSIONS_FILE}" ]]; then
    log_error "${VERSIONS_FILE} not found"
    exit 1
fi
# shellcheck source=../config/versions.env
source "${VERSIONS_FILE}"

# The tag lands in a URL handed to uv: accept release tags only.
if [[ ! "${SDLC_CONTROLLER_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "SDLC_CONTROLLER_TAG must look like v1.2.3 (got '${SDLC_CONTROLLER_TAG:-}') in ${VERSIONS_FILE}"
    exit 1
fi
if [[ ! "${SDLC_CONTROLLER_PYTHON:-}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    log_error "SDLC_CONTROLLER_PYTHON must look like 3.12 (got '${SDLC_CONTROLLER_PYTHON:-}') in ${VERSIONS_FILE}"
    exit 1
fi

if ! command -v uv &>/dev/null; then
    log_error "uv not found - it ships in the dev-env Nix profile; run the bootstrap's profile step first"
    exit 1
fi

installed_tag=""
[[ -f "${STATE_FILE}" ]] && installed_tag="$(<"${STATE_FILE}")"

if [[ "${installed_tag}" == "${SDLC_CONTROLLER_TAG}" ]] && command -v sdlc &>/dev/null; then
    log_ok "sdlc controller ${SDLC_CONTROLLER_TAG} already installed"
    exit 0
fi

log_info "Installing sdlc controller ${SDLC_CONTROLLER_TAG} on uv-managed Python ${SDLC_CONTROLLER_PYTHON}..."

uv python install "${SDLC_CONTROLLER_PYTHON}"

# --force makes a bumped tag replace the old install; --python-preference
# only-managed keeps the venv off any /nix/store interpreter.
uv tool install --force \
    --python-preference only-managed \
    --python "${SDLC_CONTROLLER_PYTHON}" \
    "${CONTROLLER_REPO}@${SDLC_CONTROLLER_TAG}#subdirectory=controller"

mkdir -p "$(dirname "${STATE_FILE}")"
echo "${SDLC_CONTROLLER_TAG}" >"${STATE_FILE}"
log_ok "sdlc controller ${SDLC_CONTROLLER_TAG} installed"
