# shellcheck shell=bash disable=SC2034
# Pinned tool versions. Renovate bumps each one through the comment above it
# (see renovate.json). The runner version is the FROM tag in the Dockerfile.

# renovate: datasource=github-tags depName=aws/aws-cli
AWS_CLI_VERSION="2.40.1"
# renovate: datasource=github-releases depName=cli/cli
GH_CLI_VERSION="2.103.3"
# renovate: datasource=github-releases depName=git-lfs/git-lfs
GIT_LFS_VERSION="3.8.1"
# renovate: datasource=github-releases depName=PowerShell/PowerShell
PWSH_VERSION="7.6.10"
# renovate: datasource=github-releases depName=mikefarah/yq
YQ_VERSION="4.54.3"
# renovate: datasource=github-releases depName=astral-sh/uv
UV_VERSION="0.13.7"

# Minor version only. The pinned uv release decides the exact patch, so the
# build stays reproducible and moves forward when uv is bumped.
PYTHON_VERSION="3.14"

# IDs match myoung34/github-runner so file ownership on mounted volumes
# carries over unchanged.
RUNNER_UID=1001
RUNNER_GID=121
DOCKER_GID=500
