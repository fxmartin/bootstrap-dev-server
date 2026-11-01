# Fleet onboarding runbook

Join a freshly provisioned dev server to the agentic fleet: its agents and `sdlc` runs show in the
XPS acm overlay as a `dev-server` column, and `herdr` on the XPS can jump into it. Everything is
configured from this repository; the steps below are the only manual ones (the Tailscale login,
secrets, interactive logins and the aggregator peer). Nothing here is hand-edited on the server.

Prerequisites: your SSH alias for the server is `dev-server`, and your tailnet ACL defines
`tag:trusted` and lets it reach the GitLab host on port 80 (see [sdlc and GitLab](../README.md#sdlc-and-gitlab)).
Run the server-side steps over `ssh dev-server`: an interactive login lands in a herdr pane (see
[Logging in](../README.md#logging-in-attaching-to-herdr)).

## 1. Bootstrap

A new server has no clone yet, so its first bootstrap runs from the URL, with the acm read token
(step 2 explains the token). From a checkout of this repository on your machine, skipping the first
line if the server already exists:

```bash
./hcloud-provision.sh --no-bootstrap
ssh dev-server
curl -fsSL https://raw.githubusercontent.com/fxmartin/bootstrap-dev-server/main/bootstrap-dev-server.sh | ACM_NIX_ACCESS_TOKEN=<read-only token> bash
```

It prompts for your Git identity, a GitHub device login and the daily report's SMTP details, then
installs Tailscale, the toolset profile, `herdr` (as a user service), `acmd` (as a user service) and
the `sdlc` controller.

The bootstrap is idempotent: re-run it after a dropped connection or after fixing anything below,
from the clone it leaves on the server:

```bash
cd ~/.local/share/bootstrap-dev-server
ACM_NIX_ACCESS_TOKEN=<read-only token> ./bootstrap-dev-server.sh
```

Once the bootstrap has finished, join the tailnet, which it cannot do for you: this prints a URL to
open in a browser. `--accept-dns` is what lets `gitlab.test` resolve (see [Post-Bootstrap: Tailscale Authentication](../README.md#post-bootstrap-tailscale-authentication)).

```bash
sudo tailscale up --advertise-tags=tag:trusted --accept-dns
```

The tag must match the tailnet policy's `tagOwners` (source of truth: nix-install
`docs/apps/security/tailscale-acl.md`). Changing the advertised tags on a node that is already
logged in logs it out until you approve the printed login URL. If Tailscale asks you to pass all
non-default flags, re-run with the full flag list it prints (for example keeping `--ssh`), and
never use `--reset`.

## 2. Secrets and logins

All interactive, all on the server. Credentials stay on the server and are never committed.

| Credential | Command | Notes |
|------------|---------|-------|
| Claude Code | `claude` | Subscription login; follow the printed URL |
| GitHub | `gh auth login` | For repos still mastered on GitHub; only if you skipped the bootstrap's device login |
| GitLab | `glab auth login --hostname gitlab.test --api-protocol http --git-protocol http` | Sign in with a token, then set the Git helper below |
| Codex | `codex login` | Only if you use Codex on this server. The bootstrap does not install it: add `codex` to `devPackages` in `flake.nix` by merge request first |
| acm read token | `ACM_NIX_ACCESS_TOKEN=<token>` on the bootstrap (step 1) | Read-only GitHub token for the private `agentic-coding-monitor` flake input; stored in `~/.config/nix/nix.conf` `access-tokens` (mode 0600). See [acmd](../README.md#acmd-agentic-coding-monitor) |

`gitlab.test` answers on plain HTTP only, so the GitLab login names both protocols. For the same
reason, create its token at `http://gitlab.test`, with the `api` and `write_repository` scopes: the
`https://` link `glab` prints does not answer.

Git needs that login too, because `sdlc` pushes with `git push`. Point Git at `glab` by name after
logging in, whatever you answered at `glab`'s own Git prompt: that prompt records this build's
`/nix/store` path, which the weekly garbage collection deletes after an upgrade.

```bash
git config --global --replace-all credential.http://gitlab.test.helper '!glab auth git-credential'
```

The bootstrap does the same for GitHub: after its device login (or when `gh` is already signed in)
it names `gh` by path-free name, like `glab`, for `github.com` and `gist.github.com`. Re-run it to
repair a server whose helper still pins a `/nix/store` path, or set it by hand:

```bash
git config --global --replace-all credential.https://github.com.helper '!gh auth git-credential'
```

Without the acm token the bootstrap logs an error naming `access-tokens`, skips the `dev-env`
profile and the `acmd` service, and carries on; add the token and re-run it (step 1). The token is
also needed by `dev`, `dev-update` and the weekly update timer.

## 3. Aggregator peer

On the XPS (the machine running the acm aggregator), add the server to `~/.config/acm/config.toml`:

```toml
[[peers]]
label = "dev-server"
ssh   = "dev-server"
socket = "/run/user/1000/acm.sock"
```

`ssh` is an SSH alias (or host) the XPS can reach non-interactively. `socket` is the remote acmd
socket the peer forwards (`ssh -L`). On this Linux server acmd listens on `$XDG_RUNTIME_DIR/acm.sock`;
the uid in `/run/user/<uid>` is `id -u` on the server. Without `socket`, acm assumes the darwin
default `~/.local/state/acm/acm.sock`, which does not exist here and shows the peer as `unreachable`.

The hardening drop-in keeps `AllowTcpForwarding no` globally (it also blocks Unix-socket forwards)
and allows local forwards for the dev user only. That change lands only when the hardening phase
runs, so re-run the bootstrap on the server **without** `--skip-security-hardening`. Then restart
the aggregator's daemon so it picks the peer up:

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

`dev-server` must show `connected` with install `nix`. (`acm peers deploy dev-server` skips it with
`SKIPPED (nix): managed by nix: bump the acm pin in nix-install`. For this server the pin is this
repository's `flake.lock`, so upgrades are a merge request here.)

```bash
herdr --machine dev-server workspace list
```

It must answer with the server's workspaces. If it errors with a version mismatch, the herdr versions
differ: the fleet runs **0.9.3**, which this flake pins on x86_64-linux (an aarch64 server keeps the nixpkgs
version, so the remote jump may not work). Compare `herdr --version` on both ends.

On the server, `~/.local/share/bootstrap-dev-server/tests/verify-server.sh` checks `sdlc`, `glab`, that
`gitlab.test` resolves and answers, and the services (`systemctl --user status herdr acmd`).
It also checks `XDG_STATE_HOME`: `systemctl --user show-environment` must list it, and `~/.profile` must export it, so
`sdlc` and `acmd` share `~/.local/state/sdlc/registry.json`. Without it the overlay shows no `sdlc` runs. After the
first bootstrap, restart herdr yourself (it ends sessions); acmd is restarted for you.

## 5. Smoke test

End to end: an `sdlc` run started on the server must appear in the XPS overlay.

1. Run `ssh dev-server`: the login lands in a herdr pane on the server. From the XPS herdr,
   `herdr --remote dev-server` jumps into the same server.
2. Pick a small, low-risk open issue in a GitLab project you can push to. `sdlc fix` runs unattended
   through to the merge, so choose a fix you accept landing without reviewing it. In the pane:

   ```bash
   git clone http://gitlab.test/root/<repo>.git
   cd <repo>
   sdlc fix <issue-number>
   ```

3. In the XPS acm overlay, the `dev-server` column shows the run and the agent working in the pane,
   until it finishes.

The smoke test passes when the run finishes and was visible in the dev-server column throughout. On a
cx33, keep to 1-2 concurrent workers (see [sdlc and GitLab](../README.md#sdlc-and-gitlab)).

If it fails: no column means step 3 or `systemctl --user status acmd`; a `glab` or `sdlc` auth or
network error means the `gitlab.test` login or the tailnet ACL (step 2, then the verify script in step 4).

## 6. Android app: fleet aggregator

The bootstrap also makes this server the always-on aggregator for acm's Android app (see
[acm fleet aggregator](../README.md#acm-fleet-aggregator-android-app)). These steps are the ones it
cannot do. Join the tailnet first: after the first `tailscale up`, run `sudo systemctl restart ntfy`.

1. **Trust the peer key.** The bootstrap prints `~/.ssh/id_acm_peers.pub`. Add it to nix-install, for
   the two Macs, and to the XPS's `authorized_keys`. Then, on the server, `acm peers` must list
   `omarchy-xps13`, `macbook-pro-m3-max` and `home-lab` as `connected`.
2. **Open the tailnet ACL** (nix-install `docs/apps/security/tailscale-acl.md`): the Pixel reaches this
   server on 22 and 2586, and this server reaches the three peers on 22.
3. **Enrol the phone.** Copy the public key the app shows into a file on the server, and print its line:

   ```bash
   acm mobile key-line --acm "$HOME/.nix-profile/bin/acm" --level p3 --name pixel-10-pro <pubkey-file>
   ```

   Add that line to `config/acm-phone-keys.pub` by merge request, or to `~/.config/acm/phone-keys.pub`
   on the server, then re-run the bootstrap. The two are alternatives: if the second file exists, the
   first is ignored.
4. **Log the ntfy app in.** Point it at `http://<tailscale-ip>:2586`, with the phone's name as user and
   `~/.config/acm/ntfy/<name>.password` as password.
5. **Check.** `~/.local/share/bootstrap-dev-server/tests/verify-server.sh` reports the peers, that the phone lines are restricted to
   `acm bridge`, and that ntfy listens on the Tailscale IP only.

To revoke a phone, remove its line and re-run the bootstrap.
