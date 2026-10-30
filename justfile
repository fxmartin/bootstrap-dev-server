# ABOUTME: Maintainer recipes for bootstrap-dev-server
# ABOUTME: flake.lock is only ever updated here, then merged to main via an MR

# Update flake.lock and validate the flake. Run on a dev machine, commit the
# new flake.lock and open a merge request - servers apply exactly what is on main.
update-lock:
    nix flake update
    nix flake check
