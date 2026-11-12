# syntax=docker/dockerfile:1
# Official runner image plus the myoung34/github-runner tool set, uv, and
# Python 3.14. Renovate bumps this tag when actions/runner releases.
FROM ghcr.io/actions/actions-runner:2.338.2

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python

COPY --chmod=0755 build/ /tmp/build/
RUN /tmp/build/install.sh

# Same user and working directory as the base image. ARC starts the runner
# with /home/runner/run.sh.
USER runner
WORKDIR /home/runner
