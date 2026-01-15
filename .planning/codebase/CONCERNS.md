# Codebase Concerns

**Analysis Date:** 2026-01-15

## Tech Debt

**Large Monolithic Scripts:**
- Issue: Main bootstrap script is 1808 lines in single file
- Files: `bootstrap-dev-server.sh`, `hcloud-provision.sh` (993 lines)
- Why: Designed for single-command curl|bash execution
- Impact: Harder to test individual functions, longer load times
- Fix approach: Consider splitting into sourced modules while maintaining single-file distribution

**Large Inline Shell Configuration:**
- Issue: shellHook in flake.nix contains ~280 lines of inline bash
- File: `flake.nix` lines 179-459
- Why: Ensures all configuration happens in Nix shell entry
- Impact: Hard to debug, can't be tested separately, runs on every shell entry
- Fix approach: Extract to external scripts sourced from shellHook

**Duplicated MCP Server Configuration:**
- Issue: Same MCP server config repeated 3 times in flake.nix
- File: `flake.nix` (devShells.default, minimal, python)
- Why: Each dev shell needs its own shellHook
- Impact: Config drift risk, maintenance overhead
- Fix approach: Extract to shared function or external config file

## Known Bugs

**Shellcheck Warning SC2155:**
- Symptoms: Multiline variable assignment can mask return values
- Trigger: `local entry="...(command substitution)"` pattern
- File: `hcloud-provision.sh` line 683
- Workaround: None needed (cosmetic warning)
- Root cause: Multiline string with embedded command
- Fix: Split declaration and assignment: `local entry; entry="..."`

## Security Considerations

**Curl-Pipe-Bash Installation Pattern:**
- Risk: Remote code execution from untrusted source
- Files: `bootstrap-dev-server.sh`, `hcloud-provision.sh`, `README.md`
- Current mitigation: Uses HTTPS, trusted GitHub repository
- Recommendations: Document checksum verification, add integrity checking option

**Tailscale Installation Script:**
- Risk: Pipes from external URL without verification
- File: `bootstrap-dev-server.sh` line 657
- Current mitigation: HTTPS, reputable source (tailscale.com)
- Recommendations: Add checksum verification or document manual verification

**Geoip-Shell Installation Without Pinning:**
- Risk: Git clone without tag/commit pinning
- File: `bootstrap-dev-server.sh` lines 589-594
- Current mitigation: `--depth 1` limits exposure
- Recommendations: Pin to specific tag with `--branch vX.Y.Z`

**Templated Secrets in Configuration:**
- Risk: Users may forget to replace placeholder tokens
- File: `flake.nix` lines 210, 433 (`YOUR_TOKEN_HERE`, `YOUR_PASSWORD_OR_APP_PASSWORD`)
- Current mitigation: Shell output reminds user to configure
- Recommendations: Add startup check for unconfigured tokens with warning

## Performance Bottlenecks

**GSD Installation on Shell Entry:**
- Problem: `npx --yes get-shit-done-cc --global` runs if marker file missing
- File: `flake.nix` lines 269-280
- Measurement: Can take 5-10 seconds, blocks shell initialization
- Cause: npm network fetch on first run
- Improvement path: Add timeout wrapper, run in background, or pre-install in flake

**Symlink Health Check on Every Entry:**
- Problem: `ensure_symlink()` runs filesystem operations on every shell entry
- File: `flake.nix` lines 243-267
- Measurement: Milliseconds, but unnecessary after first run
- Cause: No caching of successful symlink state
- Improvement path: Add marker file to skip repeated checks

## Fragile Areas

**SSH Restart Deferral:**
- File: `bootstrap-dev-server.sh`
- Why fragile: SSH restart must happen last to avoid disconnection
- Common failures: Forgot to call `restart_ssh_final()`, called too early
- Safe modification: Search for all `SSH_RESTART_NEEDED` references
- Test coverage: Only tested via grep for function existence

**Nix Flake Input Pinning:**
- File: `flake.nix` lines 19-23
- Why fragile: Node.js 22 requirement for MCP servers
- Common failures: nixpkgs update breaks MCP server builds
- Safe modification: Check mcp-servers-nix compatibility before updating
- Test coverage: `tests/flake.bats` validates syntax only

## Scaling Limits

**Single Server Focus:**
- Current capacity: One server per provision run
- Limit: No batch provisioning support
- Symptoms at limit: Must run script repeatedly for multiple servers
- Scaling path: Add batch mode with server name list

## Dependencies at Risk

**Sequential Thinking MCP Server:**
- Risk: Disabled due to upstream build broken (issue #285)
- File: `flake.nix` line 37 (comment only)
- Impact: Feature unavailable until upstream fixes
- Migration plan: Monitor issue, re-enable when fixed

**Node.js 22 Pinning:**
- Risk: nixpkgs may upgrade beyond Node.js 22
- File: `flake.nix` lines 19-23
- Impact: MCP server builds could break
- Migration plan: Document in CLAUDE.md, add version check

## Missing Critical Features

**No Batch Server Provisioning:**
- Problem: Can only provision one server at a time
- Current workaround: Run script multiple times
- Blocks: Automated fleet deployment
- Implementation complexity: Medium (loop with server name list)

**No Dry-Run Mode:**
- Problem: Can't preview what bootstrap will do
- Current workaround: Read the script manually
- Blocks: Safe testing of configuration changes
- Implementation complexity: Low (add --dry-run flag)

## Test Coverage Gaps

**No Live System Tests:**
- What's not tested: Actual SSH hardening, firewall rules, service starts
- Risk: Configuration could be syntactically correct but functionally broken
- Priority: Medium (design philosophy is no live tests)
- Difficulty to test: Would require test VM or container

**Bootstrap Functions Only String-Tested:**
- What's not tested: Actual function execution with real system state
- File: `tests/bootstrap.bats` (mostly grep-based tests)
- Risk: Function could exist but not work correctly
- Priority: Medium
- Difficulty to test: Requires mocking entire system state

**No Flake Build Verification:**
- What's not tested: Whether flake.nix actually builds successfully
- File: `tests/flake.bats` only validates syntax
- Risk: Flake could parse but fail to build
- Priority: Low (would require Nix in CI)
- Difficulty to test: CI environment needs Nix daemon

---

*Concerns audit: 2026-01-15*
*Update as issues are fixed or new ones discovered*
