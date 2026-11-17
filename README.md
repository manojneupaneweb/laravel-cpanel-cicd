# Laravel cPanel CI/CD

Reusable GitHub Actions deployment for Laravel applications on cPanel. Each application keeps its own repository and calls one shared workflow. The workflow SSHes to the server, fast-forwards the existing Git checkout, installs PHP dependencies, and runs only the Laravel steps that application has enabled.

This repository is the deployment template. It does not contain an application, a production `.env`, or server credentials.

## Architecture

```text
Laravel repository                         This template
.github/workflows/deploy.yml               .github/workflows/reusable-deploy.yml
        |                                              |
        |  uses: .../reusable-deploy.yml@main          |
        +-----------------------> GitHub-hosted runner |
                                       |               |
                         SSH, pinned host key          |
                                       v               |
                                 cPanel account        |
                          git fetch  <--- GitHub deploy key on the server
```

Two SSH identities are involved:

1. GitHub Actions authenticates to cPanel with `SSH_PRIVATE_KEY`.
2. cPanel authenticates to GitHub with a separate read-only deploy key, or with HTTPS credentials stored on the server, when it runs `git fetch`.

Those keys are created and stored independently. Setup for both is in [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Features

- Reusable `workflow_call` workflow with per-application PHP, Composer, path, branch, and feature flags
- Manual runs through `workflow_dispatch` on the caller workflow
- Concurrency lock per repository, environment, and path
- Pinned third-party actions and required SSH host-key checking
- Fast-forward only deployment, with a hard stop when tracked server files changed
- Composer install through a configurable PHP binary, including `/opt/alt/php84/usr/bin/php /usr/local/bin/composer`
- Frontend build on the server or on the GitHub runner
- MySQL, MariaDB, and SQLite backups before an optional migration
- Config and view caching, with optional route cache, event cache, queue restart, and maintenance mode
- Artisan and HTTP health checks
- Release SHA recorded on the server
- Failure annotation without automatic database restore
- Manual rollback script

## Requirements

- A Laravel checkout already present on cPanel, with `artisan`, `composer.json`, `.git`, and a mode `640` or `600` `.env`
- PHP and Composer paths available to the SSH user
- `git`, `bash`, `flock`, and, for MySQL backups, `mysqldump`
- A GitHub-hosted runner can reach the cPanel SSH port
- The server can reach GitHub for `git fetch`

The template does not assume Vite, a queue worker, the scheduler, a particular database, or a particular Laravel release. `route:cache` and `queue:restart` are off unless the caller enables them.

## Installation

Follow [docs/INSTALLATION.md](docs/INSTALLATION.md). The short version:

1. Copy [examples/laravel-caller.yml](examples/laravel-caller.yml) to `.github/workflows/deploy.yml` in the Laravel repository.
2. Replace the account path, PHP binary, health URL, and branch.
3. Create the two SSH credentials described in [docs/CONFIGURATION.md](docs/CONFIGURATION.md).
4. Add `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, and `SSH_KNOWN_HOSTS` to the Laravel repository or its `production` environment.
5. Run the Deploy workflow manually once.

## Example caller

The example below is the same contract as [examples/laravel-caller.yml](examples/laravel-caller.yml). The paths are placeholders.

```yaml
name: Deploy

on:
  workflow_dispatch:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  deploy:
    uses: manojneupaneweb/laravel-cpanel-cicd/.github/workflows/reusable-deploy.yml@main
    with:
      php_version: "8.4"
      php_binary: /opt/alt/php84/usr/bin/php
      composer_path: /usr/local/bin/composer
      composer_mode: php
      production_branch: main
      deployment_path: /home/account/apps/example
      ssh_port: "22"
      frontend_mode: none
      run_migrations: false
      backup_database: true
      health_check_url: https://example.com/up
      environment: production
    secrets:
      SSH_HOST: ${{ secrets.SSH_HOST }}
      SSH_USER: ${{ secrets.SSH_USER }}
      SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
      SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
```

More input fields are documented in [docs/CONFIGURATION.md](docs/CONFIGURATION.md). [config/deployment.example.yml](config/deployment.example.yml) is the same contract in a reference file. The scripts read environment variables from the workflow, not that file.

## Deployment process

[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) lists every server step. The release fetches Git history and fast-forwards. It does not use `git reset --hard` or `git clean`. Migrations run only when both `run_migrations` and `backup_database` are true.

## Troubleshooting and rollback

- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- [docs/ROLLBACK.md](docs/ROLLBACK.md)
- [docs/SECURITY.md](docs/SECURITY.md)

## Repository layout

```text
.github/workflows/reusable-deploy.yml   Shared deployment workflow
.github/workflows/validate.yml           Syntax, ShellCheck, and secret checks
scripts/deploy.sh                        Release sequence
scripts/backup.sh                        MySQL, MariaDB, and SQLite backup
scripts/health-check.sh                  Artisan sanity check
scripts/rollback.sh                      Manual ancestor rollback
scripts/validate-environment.sh          Server precondition checks
examples/laravel-caller.yml              Caller copied into an application
config/deployment.example.yml            Input reference
docs/                                    Setup, security, and operations
```

## Status of this template

The workflow and scripts are published for reuse. Syntax checks are described in the commit that added them and can be re-run with the commands in `validate.yml`. A green syntax check is not a production deployment. No cPanel application is deployed by publishing this repository.
