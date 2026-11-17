# Configuration

Two independent credentials are required. Mixing them up is the usual reason a first deployment fails.

## GitHub Actions connects to cPanel

This connection lets the workflow open an SSH session and run `scripts/deploy.sh`.

1. Create a dedicated SSH key pair on a trusted machine. Do not commit either file.

```bash
ssh-keygen -t ed25519 -f ./cpanel-actions -C "github-actions-cpanel"
```

2. Put the public key in the cPanel account's `~/.ssh/authorized_keys`.
3. Store the private key in the GitHub secret `SSH_PRIVATE_KEY`. Include the `BEGIN` and `END` lines.
4. Store the SSH hostname in `SSH_HOST` and the account username in `SSH_USER`.

Pin the server host key. Read the public key from the server, or from the host administrator, and compare the fingerprint before saving it:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

The secret `SSH_KNOWN_HOSTS` contains one or more lines in OpenSSH format. For port 22:

```text
ssh.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleReplaceWithTheRealKey
```

For any other port, include the port in brackets:

```text
[ssh.example.com]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleReplaceWithTheRealKey
```

The workflow writes this value to `known_hosts` and connects with `StrictHostKeyChecking=yes`. It does not run `ssh-keyscan` during deployment and it does not set `StrictHostKeyChecking=no`.

`ssh-keyscan` can collect a key during initial setup. Compare that fingerprint with the key printed on the server before you store the secret.

## cPanel pulls source code from GitHub

This connection is used by `git fetch` on the server. The Actions SSH key is not reused for it.

On the cPanel server, create a read-only deploy key for the Laravel repository:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github-readonly -C "cpanel-readonly"
```

Add `~/.ssh/github-readonly.pub` to the Laravel repository as a read-only deploy key. Point the application remote at GitHub over SSH:

```bash
git -C ~/apps/example remote set-url origin git@github.com:OWNER/APPLICATION.git
```

Use an SSH config entry so Git uses that key:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github-readonly
  IdentitiesOnly yes
```

An HTTPS remote with a fine-grained personal access token stored in the server credential store is an alternative. Keep that token on the server. Do not place it in this template or in the workflow logs.

Test the server connection before the first workflow run:

```bash
git -C ~/apps/example fetch origin main
```

## Caller inputs

[examples/laravel-caller.yml](../examples/laravel-caller.yml) is a valid caller. Copy it to the Laravel repository and change the values.

| Input | Meaning |
| --- | --- |
| `php_version` | Major.minor version that `php_binary` must report, such as `8.4` |
| `php_binary` | Absolute PHP path on the server |
| `composer_path` | Composer phar or binary |
| `composer_mode` | `php` runs `php_binary composer_path`; `direct` runs `composer_path` |
| `composer_flags` | Allowlisted flags. Unknown flags fail the release |
| `production_branch` | Branch already checked out on the server |
| `deployment_path` | Absolute application directory |
| `ssh_port` | SSH port, default `22` |
| `frontend_mode` | `none`, `server`, or `runner` |
| `run_migrations` | `true` runs `php artisan migrate --force` |
| `backup_database` | `true` backs up MySQL, MariaDB, or SQLite |
| `optimize` | Cache config and views |
| `cache_routes` | Also run `route:cache` |
| `cache_events` | Run `event:cache` when Artisan provides it |
| `restart_queues` | Run `queue:restart` |
| `maintenance_mode` | Put the site in maintenance mode during the release |
| `health_check_url` | Public URL. Empty skips the URL check |
| `health_check_from` | `runner` or `server` |
| `environment` | GitHub Environment used for secrets and protection rules |
| `git_remote` | Remote name on the server, usually `origin` |
| `template_repository` | This template, `manojneupaneweb/laravel-cpanel-cicd` |
| `scripts_ref` | Script ref, usually the same ref as the workflow `uses` line |

`composer_mode: php` is the setting that supports a cPanel command of the form:

```bash
/opt/alt/php84/usr/bin/php /usr/local/bin/composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
```

Pass those two paths as `php_binary` and `composer_path`.

Migrations require a backup. If `run_migrations` is `true` and `backup_database` is `false`, the script stops before migrating.

Route caching is off unless `cache_routes` is `true`. Leave it false for applications that register closure routes.

## Secrets passed to the reusable workflow

Reusable workflows do not automatically receive repository secrets. The caller maps them:

```yaml
secrets:
  SSH_HOST: ${{ secrets.SSH_HOST }}
  SSH_USER: ${{ secrets.SSH_USER }}
  SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
  SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
```

You can store those four secrets on the GitHub Environment named by `environment`. The job requests that environment, so environment protection rules apply.
