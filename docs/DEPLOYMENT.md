# Deployment

## What runs

The caller workflow starts `.github/workflows/reusable-deploy.yml`. One job runs on a GitHub-hosted runner and then connects to cPanel.

The job:

1. Validates inputs and the presence of the SSH secrets.
2. Checks out this template at `scripts_ref`.
3. When `frontend_mode` is `runner`, checks out the Laravel repository, installs Node, and runs the selected package script.
4. Installs the SSH private key and pinned `known_hosts` with mode `600` for the key.
5. Copies `scripts/` to `~/.laravel-cpanel-cicd/bin` on the server.
6. Runs `scripts/deploy.sh`.
7. When assets were built on the runner, uploads `public/build/` without deleting other public files.
8. Requests `health_check_url` from the runner unless the check was configured to run on the server.
9. On failure, emits a GitHub Actions error. It does not restore a database backup.

Concurrency is grouped by caller repository, environment, and deployment path. A second run waits. It is not cancelled in progress.

## Server sequence

`scripts/deploy.sh` calls the other scripts in this order:

1. `validate-environment.sh` checks PHP, Composer, Git, `.env` permissions, disk space, and writable Laravel directories.
2. The script takes a non-blocking lock.
3. It rejects tracked local modifications.
4. It fetches the configured remote and fast-forwards with `git merge --ff-only`.
5. It installs Composer dependencies with the configured PHP binary.
6. It builds frontend assets when `frontend_mode` is `server`.
7. It runs `backup.sh` when a backup is enabled.
8. It optionally enables maintenance mode.
9. It migrates only when `run_migrations` is true and a backup was enabled.
10. It caches configuration and views when `optimize` is true. Route and event caches, and `queue:restart`, run only when their inputs are true.
11. `health-check.sh` runs `php artisan --version`.
12. It appends the commit SHA to the release log and releases the lock.

Maintenance mode is turned off on success and on failure.

## Frontend choices

| Mode | Where assets are built | When to use it |
| --- | --- | --- |
| `none` | Nowhere | The repository already contains the built files, or the application has no asset build |
| `server` | cPanel, using npm, Yarn, or pnpm | Node.js is installed for the SSH user |
| `runner` | GitHub-hosted runner, then `rsync` of `public/build/` | The server does not have Node.js |

`runner` expects the build to create `public/build`, which matches the default Vite output used by current Laravel applications. An older Laravel Mix application that writes to `public/css` and `public/js` should commit those files or build on the server.

## Health check

Leave `health_check_url` empty to skip the HTTP check. Laravel applications that register the built-in health route can use `https://example.com/up`.

A failed HTTP check fails the GitHub job after the server commit has already fast-forwarded. The job does not roll the code or database back.

## Manual runs

Keep `workflow_dispatch` on the caller, as in [examples/laravel-caller.yml](../examples/laravel-caller.yml). The reusable workflow itself is only `workflow_call`, because a reusable workflow is selected as a job with `uses`, not as a step inside another job.

## Failure output

The failed step remains expanded in the Actions log. The final step adds an annotation that states the repository, branch, and that no backup was restored. SSH private keys are stored as secrets so GitHub masks those values if a command prints them. The scripts do not print `.env` values.
