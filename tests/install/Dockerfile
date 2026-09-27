# Test machine for install.sh: Debian with a non-root user and no sudo.
# tests/install/run.sh builds it once per job with different packages.
ARG BASE=debian:13
FROM ${BASE}
ARG PKGS="ca-certificates curl git fontconfig xz-utils"
# The apt lists stay in the image (like on a real desktop), so the user can
# run "apt-get download" for apt_extract.
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${PKGS} \
  && useradd --create-home --shell /bin/bash dev
USER dev
WORKDIR /home/dev
