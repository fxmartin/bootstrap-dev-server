# Epic 01: Agentic Fleet Host

## Epic Overview
**Epic ID**: Epic-01
**Description**: Make the Hetzner dev server a full member of FX's agentic coding fleet, configured from this repository only. The dev toolset becomes the user's default environment, so logins, non-interactive ssh and user services all see the same tools, with no `dev` step. herdr replaces tmux as the persistent session layer and runs as a user service. acmd (agentic-coding-monitor) and the sdlc controller are installed from pinned sources, so the XPS aggregator shows the server's agents and sdlc runs as a fourth machine column, and `sdlc fix` / `sdlc build` can run there.
**Business Value**: On 2026-10-30 the server could not join the fleet cleanly:
- The tools exist only inside `nix develop` (the `dev` function). Anything that is not an interactive shell runs on bare Ubuntu: `rg` is "command not found" over `ssh dev '…'`, and a user service has no claude, gh or uv.
- The running herdr server is 0.9.1, installed into `~/.nix-profile` by hand, outside this repo. The dev shell's client is 0.9.5, and the rest of the fleet runs 0.9.3.
- Two places mutate the box outside git: the weekly `nix-flake-update` timer and `dev-update` both run `nix flake update` on the server, leaving an uncommitted `flake.lock` that no repo has seen.
- tmux auto-launches on ssh, so herdr runs nested inside tmux, with two prefix keys.
- No acmd and no sdlc: the server is invisible to the acm overlay, and sdlc runs cannot go there.

**Success Metrics**:
- `ssh dev 'rg --version && claude --version && herdr --version && sdlc --version && acm --version'` succeeds with no `dev` step.
- `acm peers` on the XPS lists `dev-server` as `connected`, install `nix`, and the overlay shows its agents and sdlc runs.
- After a weekly update, `git -C ~/.local/share/bootstrap-dev-server status --short` is empty: the box runs exactly what is on `main`.
- An `sdlc fix` started in a herdr pane on the server finishes and shows in the dev-server column.

## Epic Scope
**Total Stories**: 7 | **Total Points**: 22 | **MVP Stories**: 7

Decided with FX on 2026-10-30:
- Every change goes through this repository (branch, MR, green pipeline). Nothing is hand-edited on the machine. The only manual steps are secrets and interactive logins (Story 01.3-003).
- The toolset becomes the default user profile; `dev` stays for the extra shells (`minimal`, `python`).
- herdr replaces tmux. The `tmux` package stays one more cycle as a fallback; its auto-launch and `configure_tmux` go now.
- acmd comes from the agentic-coding-monitor flake (its `packages.acm`), not from `acm peers deploy`, so the aggregator reports the install as `nix` and deploy refuses to touch it.

Decided by FX on 2026-10-30: herdr is aligned with the rest of the fleet at **0.9.3** (the XPS runs the upstream binary from a local pacman package, both Macs the upstream binary through a nix-install overlay). This flake's nixpkgs ships 0.9.5, so Story 01.2-001 pins 0.9.3. Remote jump and `herdr machine add` need the same version on both ends.

## Constraints (from CLAUDE.md)
- Claude never runs `bootstrap-dev-server.sh`, `hcloud-provision.sh` or anything that changes a live system. FX runs the bootstrap on the server and validates.
- CI is `shellcheck` and `bats` only, offline, without nix, hcloud, tailscale or gh. Tests check scripts and generated unit and config content statically (grep or function-level tests with stubs, as the existing suites do); `nix flake check` is run locally by FX.
- Shell: `set -euo pipefail`, `ABOUTME:` headers, `lib/logging.sh`, shellcheck clean, `shfmt -i 4`. Nix: nixfmt-rfc-style, `follows` on inputs.
- Re-running the bootstrap is idempotent and rewrites a generated file only when its content drifts (the `install_systemd_unit` pattern).

## Features

### Feature 01.1: The toolset is the default environment

##### Story 01.1-001: Install the dev toolset as the user's default Nix profile
**User Story**: As FX, I want the dev shell's tools on my PATH in every context (an interactive login, `ssh dev '<cmd>'`, a systemd user service, a herdr pane) so that agents, sdlc and acmd all see the same environment and I never type `dev` first.
**Priority**: Must Have
**Story Points**: 5

**Acceptance Criteria**:
- **Given** `flake.nix` **Then** it exposes `packages.<system>.dev-env`: a `buildEnv` of exactly the package list `devShells.default` uses today. The list is defined once (a `let` binding) and shared by the env and the shell, so the two cannot drift.
- **Given** the bootstrap on a server **When** it runs **Then** it installs or upgrades that env as the user's profile (`nix profile install` the first time, `nix profile upgrade` after), and is idempotent: a second run with an unchanged flake changes nothing.
- **Given** a fresh login **Then** `~/.nix-profile/bin` holds the toolset (claude, herdr, uv, gh, git, rg, fd, jq …), and it is on PATH for login and non-interactive shells: `ssh dev 'rg --version'` works.
- **Given** the dev shell's `shellHook` side effects (the Claude config symlinks, MCP pruning, msmtp and zshrc templates) **Then** they move to the bootstrap (or a script it runs), so they no longer depend on someone entering `dev`. The `dev` function still works and still enters `nix develop` for `default`, `minimal` and `python`.
- **Given** a stray profile entry installed by hand (today: a `herdr` 0.9.1 package in `~/.nix-profile`) **Then** the bootstrap removes it, logging what it removed, so the profile holds only what the flake declares.
- **Given** `tests/flake.bats` **Then** it asserts that `dev-env` exists, that the shared package list is used by both outputs, and that the bootstrap's profile step calls `nix profile` with the repo's flake reference (stubbed `nix`).

**Technical Notes**:
- Home-manager is an alternative, but it adds a second system to learn on a box this repo already owns; `buildEnv` plus `nix profile` stays within the current design. Revisit if dotfile management grows.
- Keep `allowUnfree = true` for Claude Code in the env as well.

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: none
**Risk Level**: Medium

##### Story 01.1-002: The repository is the only source of `flake.lock`
**User Story**: As FX, I want lock updates to happen in the repository and the server to apply exactly what is on `main`, so that the box never carries an uncommitted `flake.lock` and every package change is reviewed and reversible.
**Priority**: Must Have
**Story Points**: 3

**Acceptance Criteria**:
- **Given** the weekly `nix-flake-update` service (both the plain unit and the notification variant written by `configure_update_notifications`) **Then** it no longer runs `nix flake update`. It hard-resets the checkout to `origin/main` (`git fetch` + `git reset --hard origin/main`), builds the env (`nix build …#dev-env`), and only on success upgrades the profile (Story 01.1-001). A failed build leaves the previous profile in place and reports `failed`, as today.
- **Given** the `dev-update` shell function **Then** it does the same pull-and-apply and never runs `nix flake update`. It prints the commit it applied.
- **Given** a maintainer who wants newer packages **Then** the README documents the flow: `nix flake update` in a checkout on a dev machine, then an MR with the new `flake.lock`. A `just update-lock` (or equivalent) recipe in the repo does the update and runs `nix flake check`.
- **Given** a box whose checkout has local changes to tracked files **When** the service runs **Then** it logs the discarded diff (file list and short stat) before the reset, so nothing vanishes silently.
- **Given** `tests/` **Then** a bats test asserts that the generated service units and `dev-update` contain no `nix flake update`, and that they reset to `origin/main` before building.

**Technical Notes**:
- The existing units rewrite themselves on content drift (`install_systemd_unit`), so the change reaches provisioned servers on the next bootstrap run.

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: 01.1-001
**Risk Level**: Low

### Feature 01.2: herdr replaces tmux

##### Story 01.2-001: herdr server as a systemd user service, at the fleet version
**User Story**: As FX, I want the herdr server to start at boot from the repo's pinned herdr, so that agent panes survive disconnects and reboots, the server and client versions match the rest of the fleet, and panes inherit the full toolset.
**Priority**: Must Have
**Story Points**: 3

**Acceptance Criteria**:
- **Given** the flake **Then** herdr is **0.9.3**, the fleet version, through an overlay on nixpkgs' `herdr`, as nix-install does on the Macs (`darwin/configuration.nix`): upstream's own release binary, fetched and pinned by hash, no source build. On x86_64-linux the source is `https://github.com/herdrdev/herdr/releases/download/v0.9.3/herdr-linux-x86_64` with hash `sha256-GKjcZfHC+khYhDRDVt6hz9kRxvBs9G+njhk/QIf026c=` (the same file and SHA-256 as the XPS's pacman package, `18a8dc65…f4dba7`). Other systems keep `prev.herdr`. The env (`devPackages`), `devShells.default` and the service all use this one derivation; `herdr --version` in the env prints `herdr 0.9.3`. A comment says to drop the overlay once the fleet moves to a version nixpkgs ships.
- **Given** the bootstrap **Then** it writes `~/.config/systemd/user/herdr.service`, rewritten only on content drift. `ExecStart` is `herdr server` from `~/.nix-profile/bin` (or the store path from the env), with `PATH` set to the profile so every pane gets the toolset. `Restart=on-failure` and `WantedBy=default.target`. Then `daemon-reload`, `enable --now`, and `loginctl enable-linger` when linger is off.
- **Given** a herdr server already running outside the unit (today: PID from `~/.nix-profile/bin/herdr server` 0.9.1) **Then** the bootstrap stops it **only after warning** that stopping a server ends its sessions, and only when `--restart-herdr` (or an env equivalent) is passed. Without the flag it logs the conflict and leaves the old server running.
- **Given** the socket **Then** it stays at `~/.config/herdr/herdr.sock`, the path acmd and `herdr machine add` expect.
- **Given** `tests/` **Then** a bats test checks the unit's content (ExecStart, PATH, Restart, WantedBy), the linger step, that the stop path requires the flag, and that `flake.nix` pins herdr `0.9.3` with the hash above.

**Technical Notes**:
- Remote jump from the XPS (`herdr --remote`) and `herdr machine add` need equal versions on both ends.

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: 01.1-001
**Risk Level**: Medium

##### Story 01.2-002: An ssh login attaches to herdr, not tmux
**User Story**: As FX, I want `ssh dev` to drop me into my herdr session, so that I resume my agents straight away and never get herdr nested inside tmux.
**Priority**: Must Have
**Story Points**: 2

**Acceptance Criteria**:
- **Given** an interactive ssh login (`SSH_TTY` set, no `SSH_ORIGINAL_COMMAND`, not already inside herdr) **Then** the login shell attaches the herdr client to the running server. Leaving herdr returns to the plain login shell.
- **Given** a non-interactive ssh command (`ssh dev '<cmd>'`, scp, acmd's forward, `acm peers` probes) **Then** nothing attaches and nothing prints to stdout.
- **Given** `NO_HERDR=1` in the environment (e.g. `ssh -o SetEnv=NO_HERDR=1 dev`, with `AcceptEnv NO_HERDR` in the hardened sshd config) **Then** the login skips the attach, as an escape hatch.
- **Given** the tmux auto-launch block in the generated zsh config and `configure_tmux` in the bootstrap **Then** both are removed. The bootstrap removes its own marked block from an existing `~/.tmux.conf` and `~/.zshrc`, leaving anything outside the markers untouched. The `tmux` package stays in the env for one more cycle.
- **Given** the shell config that holds the attach **Then** it lives in a marked block that the bootstrap rewrites on drift. A zshrc created once and never updated (today's `if [ ! -f "$ZSHRC" ]` in the `shellHook`) no longer exists.
- **Given** the README **Then** the tmux sections describe herdr instead, including the escape hatch.
- **Given** `tests/` **Then** a bats test runs the attach guard with stubbed `herdr` across the three cases (interactive, non-interactive, `NO_HERDR`) and asserts the tmux blocks are gone.

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: 01.2-001
**Risk Level**: Low

### Feature 01.3: Fleet services

##### Story 01.3-001: acmd from the agentic-coding-monitor flake
**User Story**: As FX, I want acmd installed and upgraded from a pinned agentic-coding-monitor flake input, so that the XPS overlay shows the server's agents, sdlc runs and vitals, and acm upgrades are an MR here, like every other change.
**Priority**: Must Have
**Story Points**: 5

**Acceptance Criteria**:
- **Given** `flake.nix` **Then** it has an `agentic-coding-monitor` input pinned by `flake.lock` (with `nixpkgs.follows`), and `acm` (acmd + acm) is part of the `dev-env` profile.
- **Given** the bootstrap **Then** it writes `~/.config/systemd/user/acmd.service`, equivalent to acm's `homeManagerModules.acmd`: `ExecStart` the profile's `acmd`, `Restart=on-failure`, `WantedBy=default.target`, `PATH` including the profile (acmd calls `sdlc` and reads herdr's socket). It is rewritten on drift, then `daemon-reload` and `enable --now`. The state directory `~/.local/state/acm` is created with mode 0700.
- **Given** the input is private (GitLab `root/agentic-coding-monitor`, GitHub mirror `fxmartin/agentic-coding-monitor`) **Then** the fetch uses a read-only token supplied by FX at bootstrap time (Story 01.3-003), stored in the user's `nix.conf` `access-tokens` with mode 0600. It is never committed. A missing token makes the acm step fail with a message naming the setting, and the rest of the bootstrap continues.
- **Given** the XPS aggregator with a `[[peers]]` entry for `dev-server` **Then** `acm peers` shows it `connected` with install `nix`, and `acm peers deploy dev-server` refuses it ("managed by nix: bump the acm pin"). The peer entry lives in the XPS config, not in this repo.
- **Given** a previous push install (`~/.local/bin/acmd`) **Then** the bootstrap removes it and its unit, so only the Nix-managed one runs.
- **Given** `tests/` **Then** a bats test checks the unit content, the 0700 state dir, the token-missing message and that no token value appears in any generated file.

**Technical Notes**:
- acm's flake already exports `packages.<system>.acm` and `homeManagerModules.acmd` (agentic-coding-monitor `flake.nix`); reuse its unit content rather than inventing one.
- Upgrading acm = bump the input in an MR (`nix flake lock --update-input agentic-coding-monitor`).

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: 01.1-001, 01.2-001
**Risk Level**: Medium

##### Story 01.3-002: sdlc controller and glab, ready for GitLab runs
**User Story**: As FX, I want the sdlc controller and glab installed from pinned sources and able to reach `gitlab.test`, so that `sdlc fix` and `sdlc build` run on the server against the local-ci-cd GitLab.
**Priority**: Must Have
**Story Points**: 3

**Acceptance Criteria**:
- **Given** the env **Then** it includes `glab`, and the login environment exports `GITLAB_HOST=gitlab.test`.
- **Given** the bootstrap **Then** it installs the controller with `uv tool install` from `git+https://github.com/fxmartin/claude-code-config@<tag>#subdirectory=controller`. The tag is pinned in one versioned file in this repo (e.g. `config/versions.env`) and bumped by MR. Re-running with the same tag changes nothing; a new tag upgrades.
- **Given** the controller's Python **Then** it is a uv-managed interpreter (`uv python install`, `--python-preference only-managed`), never a `/nix/store` Python, so Nix garbage collection cannot break `sdlc`.
- **Given** `tests/verify-server.sh` **Then** it checks `sdlc --version`, `glab --version`, that `gitlab.test` resolves (Tailscale split DNS, `tailscale up --accept-dns`), and that `http://gitlab.test` answers. A failure names the fix (accept-dns, or tailnet ACL).
- **Given** the README **Then** it recommends 1–2 concurrent workers on this server size (4 vCPU / 8 GB, cx33), or `--sequential`, and explains why: each worker runs Claude plus the repo's tests.
- **Given** `tests/` **Then** a bats test checks the pinned-tag install command, the managed-Python flags and the `GITLAB_HOST` export.

**Technical Notes**:
- claude-code-config is public on GitHub, so this needs no token. Per-repo toolchains (Go, Qt) are out of scope: a repo needing them gets its own story when it is first run here.

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: 01.1-001
**Risk Level**: Low

##### Story 01.3-003: Fleet onboarding runbook and smoke test
**User Story**: As FX, I want one runbook that lists the few manual steps (secrets, logins, the aggregator peer) and a smoke test, so that joining a new server to the fleet takes minutes and I know it works end to end.
**Priority**: Should Have
**Story Points**: 1

**Acceptance Criteria**:
- **Given** `docs/fleet-onboarding.md` **Then** it lists, in order:
  1. the bootstrap run;
  2. the manual secrets and logins: `claude` (subscription login), `gh auth login`, `glab auth login` for `gitlab.test`, `codex login` if used, and the acm read token (Story 01.3-001);
  3. the `[[peers]]` entry to add on the XPS aggregator, and its restart;
  4. checks: `acm peers` shows the server `connected` and `nix`; `herdr --machine dev-server workspace list` answers from the XPS (equal herdr versions);
  5. the smoke test: an `sdlc fix` on a small issue in a herdr pane on the server, with its run visible in the dev-server overlay column.
- **Given** the README **Then** it links the runbook from the install section and from the herdr, acmd and sdlc sections.

**Definition of Done**:
- [ ] Code implemented and peer reviewed
- [ ] Tests written and passing
- [ ] User-facing docs updated in the same commit for behavior-changing diffs (README/docs/usage/help; CHANGELOG excluded)

**Dependencies**: 01.3-001, 01.3-002
**Risk Level**: Low

## Epic Progress
- [x] 01.1-001 · [x] 01.1-002
- [x] 01.2-001 · [ ] 01.2-002
- [ ] 01.3-001 · [x] 01.3-002 · [ ] 01.3-003

**Completed points**: 14 / 22 (built 2026-10-30: 01.1-001 MR !5, 01.1-002 MR !6, 01.3-002 MR !7, 01.2-001 MR !11 with OOMPolicy=continue added after review; reinstall guard #1 MR !10. Not yet run on the server.)
