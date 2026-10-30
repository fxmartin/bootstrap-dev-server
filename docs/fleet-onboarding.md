# Fleet onboarding runbook

Join a freshly provisioned dev server to the agentic fleet: its agents and `sdlc` runs show in the
XPS acm overlay as a `dev-server` column, and `herdr` on the XPS can jump into it. Everything is
configured from this repository; the steps below are the only manual ones (secrets, interactive
logins and the aggregator peer). Nothing here is hand-edited on the server.

Prerequisites: the server is on the tailnet (see [Post-Bootstrap: Tailscale Authentication](../README.md#post-bootstrap-tailscale-authentication)),
with split DNS accepted (`--accept-dns`) so `gitlab.test` resolves, and your SSH alias for it is
`dev-server`. Run the server-side steps over `ssh dev-server`, inside a herdr pane where noted.

## 1. Bootstrap

Run the bootstrap on the server with the acm read token (step 2 explains the token), from a shell
outside herdr:

```bash
ACM_NIX_ACCESS_TOKEN=<read-only token> ./bootstrap-dev-server.sh
```

Or, for a new server, `./hcloud-provision.sh --no-bootstrap`, then `ssh dev-server` and the one-liner in
[acmd](../README.md#acmd-agentic-coding-monitor). The bootstrap is idempotent: re-run it after fixing
anything below. It installs the toolset profile, `herdr` (as a user service), `acmd` (as a user service)
and the `sdlc` controller.

## 2. Secrets and logins

All interactive, all on the server. Credentials stay on the server and are never committed.

| Credential | Command | Notes |
|------------|---------|-------|
| Claude Code | `claude` | Subscription login; follow the printed URL |
| GitHub | `gh auth login` | For repos still mastered on GitHub |
| GitLab | `GITLAB_HOST=gitlab.test glab auth login` | Host `gitlab.test`; login shells already export `GITLAB_HOST` |
| Codex | `codex login` | Only if you use Codex on this server |
| acm read token | `ACM_NIX_ACCESS_TOKEN=<token> ./bootstrap-dev-server.sh` | Read-only GitHub token for the private `agentic-coding-monitor` flake input; stored in `~/.config/nix/nix.conf` `access-tokens` (mode 0600) |

Without the acm token the bootstrap logs an error naming `access-tokens`, skips the `dev-env`
profile and the `acmd` service, and carries on; add the token and re-run it (step 1). The token is
also needed by `dev`, `dev-update` and the weekly update timer.

## 3. Aggregator peer

On the XPS (the machine running the acm aggregator), add the server to `~/.config/acm/config.toml`:

```toml
[[peers]]
label = "dev-server"
ssh   = "dev-server"
```

`ssh` is an SSH alias (or host) the XPS can reach non-interactively. Then restart the aggregator's
daemon so it picks the peer up:

```bash
systemctl --user restart acmd
```

The peer entry lives in the XPS config, not in this repository. Also save the server as a herdr
machine, if you have not already: `herdr machine add dev-server`.

## 4. Checks

From the XPS:

```bash
acm peers
```

`dev-server` must show `connected` with install `nix`. (`acm peers deploy dev-server` refuses it,
"managed by nix: bump the acm pin": upgrades are a merge request here.)

```bash
herdr --machine dev-server workspace list
```

It must answer with the server's workspaces. If it errors with a version mismatch, the herdr versions
differ: the fleet runs **0.9.3**, which this flake pins on x86_64-linux (an aarch64 server keeps the nixpkgs
version, so the remote jump may not work). Compare `herdr --version` on both ends.

On the server, `tests/verify-server.sh` checks `sdlc`, `glab`, that `gitlab.test` resolves and
answers, and the services (`systemctl --user status herdr acmd`).

## 5. Smoke test

End to end: an `sdlc` run started on the server must appear in the XPS overlay.

1. On the server, open a herdr pane (`herdr`, or `herdr --machine dev-server` from the XPS).
2. Pick a small, low-risk open issue in a GitLab project you can push to. In that repository's
   checkout in the pane, run:

   ```bash
   sdlc fix <issue-number>
   ```

3. In the XPS acm overlay, the `dev-server` column shows the run and the agent working in the pane,
   until it finishes.

The smoke test passes when the run finishes and was visible in the dev-server column throughout. On a
cx33, keep to 1-2 concurrent workers (see [sdlc and GitLab](../README.md#sdlc-and-gitlab)).

If it fails: no column means step 3 or `systemctl --user status acmd`; a `glab` or `sdlc` auth or
network error means the `gitlab.test` login or the tailnet ACL (step 2, `tests/verify-server.sh`).
