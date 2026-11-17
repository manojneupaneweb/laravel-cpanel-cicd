# Security

## Credentials

The repository must never contain a private key, database password, production `.env`, or backup. GitHub secrets supply the Actions SSH identity. The server's own deploy key or credential store supplies GitHub access for `git fetch`.

The workflow grants `contents: read` and passes only the four SSH secrets declared by `workflow_call`.

## SSH

- Authentication is key-based.
- `IdentitiesOnly=yes` prevents the runner from offering unrelated keys.
- `BatchMode=yes` prevents password prompts.
- `StrictHostKeyChecking=yes` and a caller-supplied `known_hosts` file reject unknown hosts.
- Host keys are not discovered automatically during deployment.

Use a cPanel SSH user that can write only the application account. A dedicated deployment user is preferable to a shared administrator login.

## Shell and inputs

Caller inputs are passed through the step `env` context and checked against allowlists before SSH runs. Composer flags are allowlisted again on the server. Paths must be absolute and cannot contain `..`.

Remote configuration is written with Bash `printf %q` and removed after the release script exits, including when the script fails. The file contains paths and flags, not the SSH private key and not the database password.

Database passwords are read from the server `.env` into a mode `600` MySQL option file for `mysqldump`, then the option file is deleted. The password is not printed. Values that contain a double quote, backslash, or command substitution are rejected rather than interpolated.

## Application files

The release refuses to continue when:

- `.env` is missing, world-readable, or tracked by Git
- the application directory is world-writable
- tracked files differ from the last commit
- the checkout is on a different branch from `production_branch`
- the remote history is not a fast-forward

The deployment script does not run `git reset --hard`, `git clean -fd`, or `chmod 777`. It does not delete application files and it does not write `.env`.

`git reset --keep` exists only in `scripts/rollback.sh`, and only after `CONFIRM=rollback` and an ancestor check. That script does not import a database backup.

## Database backups

Backups are written under `~/.laravel-cpanel-cicd/backups/` with directory mode `700` and file mode `600`. That directory is outside the web root when the application lives in a normal cPanel home. The script supports `mysql`, `mariadb`, and `sqlite`. Any other `DB_CONNECTION` fails when a backup was requested.

Backups are never restored automatically.

## Locks and logs

A `flock` file under `~/.laravel-cpanel-cicd/locks/` prevents overlapping releases of the same path. The recorded commit is appended to a mode `600` log under `~/.laravel-cpanel-cicd/releases/`.

## What this template does not do

It does not scan the Laravel application for vulnerabilities, rotate passwords, or prove that a particular cPanel account is hardened. Those remain part of the application and host setup.
