# Rollback

Rollback is manual. A failed deployment does not restore code or a database by itself.

## Find the previous commit

Successful releases append a line to:

```text
~/.laravel-cpanel-cicd/releases/<path-hash>/releases.log
```

Each line contains a UTC timestamp, the full commit SHA, the branch, and `success`. Choose the SHA that was live before the bad release. You can also copy it from the GitHub Actions log line `Recorded deployed commit`.

The matching database backup, when one was created, is a mode `600` file under:

```text
~/.laravel-cpanel-cicd/backups/<path-hash>/
```

`LATEST` in that directory points at the newest backup. The backup is not imported by any script.

## Move the code back

SSH to cPanel with the same user that deploys the application. The rollback script is copied to the server by a deployment, and it is also in this repository at `scripts/rollback.sh`.

```bash
DEPLOY_PATH=/home/account/apps/example \
TARGET_SHA=abc1234 \
CONFIRM=rollback \
  bash ~/.laravel-cpanel-cicd/bin/rollback.sh
```

`TARGET_SHA` must be an ancestor of the current `HEAD`. The script uses `git reset --keep` for that ancestor and refuses dirty tracked files. This is the only place a reset is used. Routine deployment uses `git merge --ff-only` instead.

After the checkout moves:

```bash
cd /home/account/apps/example
/opt/alt/php84/usr/bin/php /usr/local/bin/composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
/opt/alt/php84/usr/bin/php artisan config:cache
/opt/alt/php84/usr/bin/php artisan view:cache
```

Use the PHP and Composer paths configured for that application. Run `route:cache`, `event:cache`, or `queue:restart` only if that application was deployed with those options.

If maintenance mode is still on:

```bash
/opt/alt/php84/usr/bin/php artisan up
```

## Database

Restoring a backup is a separate decision. `backup.sh` and `rollback.sh` never run `mysql` imports or replace a SQLite file.

Before you restore a MySQL backup manually, stop writes, confirm the backup file, and keep a fresh backup of the current database. A code rollback plus an older database can drop data that was written after that backup. Prefer a forward fix when the migration is compatible with the previous code.

## When fast-forward deployment was refused

If the log says the remote is not a fast-forward, the server checkout has commits that are not on the remote branch, or the histories diverged. Do not solve that with `git reset --hard` as part of a normal deploy. Inspect `git status` and `git log --oneline --decorate -5`, identify the local commit, and decide whether it must be preserved. Only then use the rollback script or a reviewed manual Git command.
