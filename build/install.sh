#!/usr/bin/env bash
# Adds the myoung34/github-runner tool set, plus uv and Python 3.14, on top of
# the official ghcr.io/actions/actions-runner image. Runs once, as root, at
# image build time.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=versions.sh
source "${here}/versions.sh"

DEB_ARCH="$(dpkg --print-architecture)" # amd64 | arm64
UNAME_ARCH="$(uname -m)"                # x86_64 | aarch64

log() { printf '\n==> %s\n' "$*"; }

fetch() { curl -fsSL --retry 5 --retry-all-errors -o "$2" "$1"; }

# verify <file> <expected sha256>
verify() {
  echo "$2  $1" | sha256sum -c -
}

apt_install() {
  apt-get install -y --no-install-recommends "$@"
}

# --- users and groups --------------------------------------------------------
# Runs before any package install, so system groups created by packages can't
# take the IDs we want.
set_ids() {
  log "runner uid ${RUNNER_UID}, gid ${RUNNER_GID}; docker gid ${DOCKER_GID}"
  local old_runner_gid old_docker_gid
  old_runner_gid="$(id -g runner)"
  old_docker_gid="$(getent group docker | cut -d: -f3)"

  groupmod -g "${DOCKER_GID}" docker
  groupmod -g "${RUNNER_GID}" "$(id -gn runner)"
  if [ "$(id -u runner)" != "${RUNNER_UID}" ]; then
    usermod -u "${RUNNER_UID}" runner
  fi

  # groupmod doesn't re-own existing files.
  find / -xdev -gid "${old_runner_gid}" -exec chgrp -h "${RUNNER_GID}" {} +
  find / -xdev -gid "${old_docker_gid}" -exec chgrp -h "${DOCKER_GID}" {} +
}

# --- apt ---------------------------------------------------------------------
add_docker_repo() {
  # shellcheck source=/dev/null
  source /etc/os-release
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
}

install_apt_packages() {
  log "apt packages"
  apt-get update
  apt_install ca-certificates curl gnupg

  echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
  add_docker_repo
  apt-get update
  apt-get upgrade -y

  # The base image ships static docker binaries and a buildx plugin. The apt
  # packages below replace them; remove the extra plugin so there's only one.
  rm -f /usr/local/lib/docker/cli-plugins/docker-buildx

  # Called liblttng-ust1t64 on noble, liblttng-ust1 or 0 on other releases.
  local lttng=()
  mapfile -t lttng < <(apt-cache search -n '^liblttng-ust[0-9]' | awk '{print $1}' | sort -V | tail -1)

  apt_install \
    `# essentials` \
    apt-transport-https dirmngr dumb-init gosu gpg-agent jq libc-bin locales \
    sudo tar unzip xz-utils zip \
    `# development` \
    build-essential gettext libcurl4-openssl-dev libpq-dev libyaml-dev \
    lsb-release pkg-config zlib1g-dev zstd \
    `# container tools` \
    buildah podman skopeo \
    `# debugging` \
    "${lttng[@]}" \
    `# docker` \
    containerd.io docker-buildx-plugin docker-ce docker-ce-cli docker-compose-plugin \
    `# git` \
    git \
    `# network tools` \
    inetutils-ping openssh-client rsync wget \
    `# node` \
    nodejs npm \
    `# python` \
    python3 python3-pip python3-setuptools python3-venv

  locale-gen

  # docker-compose v1 command name, forwarding to the compose plugin.
  printf '#!/bin/sh\nexec docker compose --compatibility "$@"\n' > /usr/local/bin/docker-compose
  chmod 0755 /usr/local/bin/docker-compose
  # Containers usually can't raise the hard file limit.
  if [ -f /etc/init.d/docker ]; then
    sed -i 's/ulimit -Hn/# ulimit -Hn/g' /etc/init.d/docker
  fi

  rm -f /etc/apt/sources.list.d/docker.list
}

# --- tools from upstream releases ---------------------------------------------
install_aws_cli() {
  log "aws-cli ${AWS_CLI_VERSION}"
  fetch "https://awscli.amazonaws.com/awscli-exe-linux-${UNAME_ARCH}-${AWS_CLI_VERSION}.zip" /tmp/awscli.zip
  unzip -q /tmp/awscli.zip -d /tmp
  /tmp/aws/install
  rm -rf /tmp/awscli.zip /tmp/aws
}

install_git_lfs() {
  log "git-lfs ${GIT_LFS_VERSION}"
  local base="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}"
  local tarball="git-lfs-linux-${DEB_ARCH}-v${GIT_LFS_VERSION}.tar.gz"
  fetch "${base}/${tarball}" "/tmp/${tarball}"
  fetch "${base}/sha256sums.asc" /tmp/git-lfs.sha256sums
  # Lines look like "<sha256> *<file>"; the * marks binary mode.
  verify "/tmp/${tarball}" "$(awk -v f="${tarball}" '$2 == f || $2 == "*" f {print $1}' /tmp/git-lfs.sha256sums)"
  tar -xzf "/tmp/${tarball}" -C /tmp
  install -m 0755 "/tmp/git-lfs-${GIT_LFS_VERSION}/git-lfs" /usr/local/bin/git-lfs
  git lfs install --system --skip-repo
  rm -rf "/tmp/${tarball}" /tmp/git-lfs.sha256sums "/tmp/git-lfs-${GIT_LFS_VERSION}"
}

install_gh() {
  log "gh ${GH_CLI_VERSION}"
  local base="https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}"
  local deb="gh_${GH_CLI_VERSION}_linux_${DEB_ARCH}.deb"
  fetch "${base}/${deb}" "/tmp/${deb}"
  fetch "${base}/gh_${GH_CLI_VERSION}_checksums.txt" /tmp/gh.checksums
  verify "/tmp/${deb}" "$(awk -v f="${deb}" '$2 == f {print $1}' /tmp/gh.checksums)"
  apt_install "/tmp/${deb}"
  rm -f "/tmp/${deb}" /tmp/gh.checksums
}

install_yq() {
  log "yq ${YQ_VERSION}"
  fetch "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${DEB_ARCH}" /usr/local/bin/yq
  chmod 0755 /usr/local/bin/yq
}

install_powershell() {
  log "powershell ${PWSH_VERSION}"
  local arch="${DEB_ARCH/amd64/x64}"
  fetch "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${arch}.tar.gz" /tmp/pwsh.tar.gz
  install -d /opt/microsoft/powershell
  tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell
  chmod 0755 /opt/microsoft/powershell/pwsh
  ln -sf /opt/microsoft/powershell/pwsh /usr/bin/pwsh
  rm -f /tmp/pwsh.tar.gz
}

install_uv() {
  log "uv ${UV_VERSION}"
  local base="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}"
  local tarball="uv-${UNAME_ARCH}-unknown-linux-gnu.tar.gz"
  fetch "${base}/${tarball}" "/tmp/${tarball}"
  fetch "${base}/${tarball}.sha256" /tmp/uv.sha256
  verify "/tmp/${tarball}" "$(awk '{print $1}' /tmp/uv.sha256)"
  tar -xzf "/tmp/${tarball}" -C /tmp
  install -m 0755 "/tmp/uv-${UNAME_ARCH}-unknown-linux-gnu/uv" "/tmp/uv-${UNAME_ARCH}-unknown-linux-gnu/uvx" /usr/local/bin/
  rm -rf "/tmp/${tarball}" /tmp/uv.sha256 "/tmp/uv-${UNAME_ARCH}-unknown-linux-gnu"
}

install_python() {
  # UV_PYTHON_INSTALL_DIR is set in the Dockerfile, so jobs find this Python
  # without downloading anything.
  log "python ${PYTHON_VERSION} (uv-managed, ${UV_PYTHON_INSTALL_DIR})"
  uv python install "${PYTHON_VERSION}"
  # Owned by runner so a job can still add another version if it needs one.
  chown -R runner:runner "${UV_PYTHON_INSTALL_DIR}"
  uv cache clean
}

# --- runner environment ----------------------------------------------------------
configure_runner() {
  log "runner environment"
  # Tool cache for actions/setup-* (AGENT_TOOLSDIRECTORY in the Dockerfile).
  install -d -o runner -g runner "${AGENT_TOOLSDIRECTORY}"
  # Let sudo pass proxy settings through to commands.
  echo 'Defaults env_keep += "HTTP_PROXY HTTPS_PROXY NO_PROXY FTP_PROXY http_proxy https_proxy no_proxy ftp_proxy"' >> /etc/sudoers
  visudo -c
}

cleanup() {
  apt-get clean
  rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache
}

set_ids
install_apt_packages
install_aws_cli
install_git_lfs
install_gh
install_yq
install_powershell
install_uv
install_python
configure_runner
cleanup
