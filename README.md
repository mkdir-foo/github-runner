# github-runner

Runner image for the ARC scale set. It's the official
`ghcr.io/actions/actions-runner` image plus the tools below, including uv and a
uv-managed Python 3.14.

## What's added

| Category | Contents |
|---|---|
| AWS | aws-cli v2 |
| Development | build-essential, gettext, libcurl4-openssl-dev, libpq-dev, libyaml-dev, lsb-release, pkg-config, zlib1g-dev, zstd, xz-utils |
| Container tools | podman, buildah, skopeo |
| Docker | docker-ce, CLI, buildx, compose plugin, `docker-compose` shim |
| Git | git, git-lfs |
| GitHub | gh |
| Network | ping, wget, openssh-client, rsync |
| Node | nodejs, npm (Ubuntu packages) |
| PowerShell | pwsh |
| Python | python3, pip, setuptools, venv (Ubuntu), plus uv and Python 3.14 in `/opt/uv-python` |
| Other | yq, jq, gosu, dumb-init, en_US.UTF-8 locale, liblttng-ust |

`runner` is uid 1001, gid 121, and the `docker` group is gid 500.

Versions are pinned in `build/versions.sh` and in the `FROM` tag of the `Dockerfile`.

## Publishing

`.github/workflows/build.yml` builds the image and runs the `goss.yaml` checks on every push and PR. On `main`, it then pushes:

- `<user>/github-runner:<runner>-<yyyymmdd>-<sha>`: unique per build. Pin the cluster to this one.
- `<user>/github-runner:<runner>`
- `<user>/github-runner:latest`

It also rebuilds weekly to pick up Ubuntu security updates.

Repository settings it needs:

- Variable `DOCKERHUB_USERNAME`
- Secret `DOCKERHUB_TOKEN` (a Docker Hub access token with read/write scope)

## Updates

`renovate.json` bumps the base image (and with it, the runner version), every tool in `build/versions.sh`, goss, and the pinned action digests. This needs the Renovate GitHub app installed on the repo.

**Publishing a new image doesn't deploy it.** The scale set pins an exact tag in
[gitops-flux](https://github.com/faangbait/gitops-flux), in
`infrastructure/github-runners/self-hosted-helmrelease.yaml`. After a runner
version bump merges here and CI publishes the image, change the `image:` tag
there to the new `<runner>-<yyyymmdd>-<sha>` tag. Don't skip this for runner
bumps: GitHub stops sending jobs to runners that fall too far behind the latest
release. Other rebuilds (tool bumps, the weekly rebuild) also go live only
through that file.

## Using it with ARC

The scale set is a Flux HelmRelease in gitops-flux (see above). The base image
has no entrypoint, so its pod template has to start the runner:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: docker.io/<user>/github-runner:<runner>-<yyyymmdd>-<sha>
        command: ["/home/runner/run.sh"]
```

The working directory is `/home/runner/_work`.
