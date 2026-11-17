# Troubleshooting

## Host key verification failed

`SSH_KNOWN_HOSTS` does not match the server key or the port. For a non-default port the line must start with `[hostname]:port`. Update the secret from the server's public key after comparing fingerprints. Do not disable host-key checking.

## Permission denied (publickey) during the workflow SSH step

The Actions private key does not match a key in the cPanel `authorized_keys` file, or `SSH_USER` is wrong. This is the GitHub Actions to cPanel connection.

## git fetch failed on the server

The workflow SSH connection succeeded, and the separate cPanel to GitHub connection failed. Check the server deploy key, `~/.ssh/config`, and `git remote -v`. A read-only key is enough.

## Remote is not a fast-forward of HEAD

The server branch contains work that is not on the GitHub branch. The script will not discard it. See [ROLLBACK.md](ROLLBACK.md).

## Tracked production files differ from Git

Someone edited tracked files on the server. Review `git status` and move those changes into Git, or remove them deliberately, before the next deploy. Ignored files such as logs do not trigger this check.

## Checkout is on another branch

The script does not switch branches. Check out `production_branch` once during server setup.

## PHP version does not match

`php_binary` reported a different major.minor version from `php_version`. Point `php_binary` at the intended cPanel PHP, for example `/opt/alt/php84/usr/bin/php`, and set `php_version` to `8.4`.

## Composer flag is not allowed

Only `--no-dev`, `--prefer-dist`, `--no-interaction`, `--optimize-autoloader`, `--no-scripts`, `--classmap-authoritative`, and `--no-progress` are accepted.

## route:cache failed

Set `cache_routes: false`. Closure routes and some package routes cannot be cached.

## event:cache or queue:restart is unnecessary

Leave `cache_events` and `restart_queues` false for applications that do not use those features. The script does not assume either one exists.

## npm is not installed

Use `frontend_mode: runner`, or install Node for the SSH user and use `frontend_mode: server`.

## public/build was not created

The runner build did not write Vite's default directory. Build on the server, or commit the asset files and use `frontend_mode: none`.

## Backup failed before migrate

The release stops before `artisan migrate`. Fix `DB_CONNECTION`, the database credentials, or `mysqldump`. Supported backup drivers are `mysql`, `mariadb`, and `sqlite`. A password containing `"` or `\` is rejected so it cannot break the option file.

## .env is world-readable or tracked

Set mode `640` or `600`, and remove `.env` from the Git index. The workflow will not overwrite the file.

## Another deployment holds the lock

A previous SSH session still has the lock, or a deploy is running. Wait for it. The lock file is under `~/.laravel-cpanel-cicd/locks/`. Remove it only after confirming that no deploy process is running.

## Health check failed after a successful server script

The new commit is already checked out. The HTTP check did not receive a successful response. Inspect the application log in `storage/logs` and the web server error log. Use [ROLLBACK.md](ROLLBACK.md) if you need the previous commit.

## Workflow is skipped or secrets are empty

Confirm the caller uses `jobs.<id>.uses` and passes `secrets` explicitly. A reusable workflow cannot be inserted as a step of another job.
