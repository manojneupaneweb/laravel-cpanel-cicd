# Installation

This template is called by each Laravel repository. It does not deploy an application by itself.

## 1. Use this repository

The published template is:

`https://github.com/manojneupaneweb/laravel-cpanel-cicd`

Call the reusable workflow from the application repository:

```yaml
jobs:
  deploy:
    uses: manojneupaneweb/laravel-cpanel-cicd/.github/workflows/reusable-deploy.yml@main
```

Pin `@main` while you want the moving template, or replace `main` with a release tag after you create one. Set `scripts_ref` to the same ref so the shell scripts match the workflow file.

## 2. Prepare the Laravel repository

1. Add `.github/workflows/deploy.yml` using [examples/laravel-caller.yml](../examples/laravel-caller.yml).
2. Replace the example account path, PHP binary, Composer path, branch, and health URL.
3. Keep `.env`, `vendor/`, and `node_modules/` out of Git.
4. Confirm `storage/` and `bootstrap/cache/` are ignored or do not contain local machine paths that would become tracked changes.

## 3. Prepare cPanel once per application

The deployment script updates an existing checkout. It does not create the first clone.

On the cPanel account, as the SSH user that the workflow will use:

```bash
mkdir -p ~/apps/example
cd ~/apps/example
git clone git@github.com:OWNER/APPLICATION.git .
git checkout main
```

Create `.env` on the server and restrict it:

```bash
chmod 640 .env
```

Install or confirm the PHP binary and Composer you will pass to the workflow. A cPanel installation often looks like this, but the path belongs in the caller workflow rather than in this template:

```bash
/opt/alt/php84/usr/bin/php /usr/local/bin/composer --version
```

Make `storage/` and `bootstrap/cache/` writable by that same SSH user. Do not grant mode `777`.

## 4. Add GitHub secrets

In the Laravel repository, or in the GitHub Environment named by `environment`, add:

| Secret | Purpose |
| --- | --- |
| `SSH_HOST` | cPanel SSH hostname |
| `SSH_USER` | cPanel SSH user |
| `SSH_PRIVATE_KEY` | Private key that cPanel authorizes for Actions |
| `SSH_KNOWN_HOSTS` | Pinned server host key |

The next page, [CONFIGURATION.md](CONFIGURATION.md), shows how to create both SSH relationships.

## 5. Run a manual deployment

Open the Actions tab in the Laravel repository and run the Deploy workflow. The caller file enables `workflow_dispatch`, so the first run can be manual. A push to the configured branch also starts it.

Watch the job log. A successful run ends with `Deployment finished` and, when a URL is configured, an HTTP status from the runner.
