# Sandbox image: a throwaway Ubuntu that mirrors a real target machine, so the
# REAL units (their actual apt-get install/uninstall) can be exercised without
# ever touching the developer's host. Built by `make sandbox-build`; run through
# `make sandbox` (a shell) or `make sandbox-run ARGS="..."` (the orchestrator).
#
# This is deliberately separate from the dev-tools image: that one carries the
# lint/test toolchain and mounts the repo read-only with no privileges, whereas
# this one carries sudo and a normal user so a unit can install and remove real
# packages, all inside a container that is discarded on exit.
ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

# Tools the bootstrap and units assume on a fresh host, plus sudo so a non-root
# user can drive the package steps exactly as on a real machine.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl sudo \
    && rm -rf /var/lib/apt/lists/*

# A normal user with passwordless sudo, mirroring how machine-setup is meant to
# run on a real host: a regular user that escalates per step. UID/GID are build
# args so the user matches the host's, keeping the bind-mounted repo readable.
ARG SANDBOX_UID=1000
ARG SANDBOX_GID=1000
RUN set -eux; \
    # Ubuntu's base image ships a default user (uid 1000); drop whoever holds the
    # target id so `dev` can take it and the bind-mounted repo stays readable.
    if getent passwd "${SANDBOX_UID}" >/dev/null; then \
        userdel -r "$(getent passwd "${SANDBOX_UID}" | cut -d: -f1)" 2>/dev/null || true; \
    fi; \
    getent group "${SANDBOX_GID}" >/dev/null || groupadd --gid "${SANDBOX_GID}" dev; \
    useradd --uid "${SANDBOX_UID}" --gid "${SANDBOX_GID}" \
        --create-home --shell /bin/bash dev; \
    printf 'dev ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/dev; \
    chmod 0440 /etc/sudoers.d/dev

USER dev
WORKDIR /work
