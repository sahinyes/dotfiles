#!/bin/bash
# Run install.sh in fresh Debian containers as a non-root user without sudo,
# twice (the second run must change nothing), then check the result.
#
#   tests/install/run.sh [JOB...]
#
# Jobs (default: all):
#   deb12       debian:12, curl + git + cc  (treesitter OFF: glibc 2.36)
#   deb13       debian:13, curl + git + cc  (treesitter ON: parsers built)
#   deb13-nocc  debian:13 without a C compiler (treesitter OFF: no cc)
#   deb13-bare  debian:13 with wget only: no curl, no git (git via apt_extract)
#
# Environment:
#   PLATFORM             docker platform (default linux/amd64, like the laptop)
#   LOG_DIR              where job logs go (default: a new temp dir)
#   DOTFILES_TEST_CACHE  optional host dir shared as the download cache; files
#                        are still sha256-checked before use
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd -P)
REPO=$(cd "$HERE/../.." && pwd -P)
PLATFORM=${PLATFORM:-linux/amd64}
LOG_DIR=${LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install-test.XXXXXX")}
CACHE=${DOTFILES_TEST_CACHE:-}
BASE_PKGS="ca-certificates fontconfig xz-utils"

# job_config JOB: sets IMAGE, PKGS and the expectations for assert.sh.
job_config() {
  case $1 in
    deb12)
      IMAGE=debian:12 PKGS="$BASE_PKGS curl git gcc libc6-dev"
      EXPECT_TS=off EXPECT_TS_REASON="glibc 2.36" EXPECT_GIT=system
      ;;
    deb13)
      IMAGE=debian:13 PKGS="$BASE_PKGS curl git gcc libc6-dev"
      EXPECT_TS=on EXPECT_TS_REASON="" EXPECT_GIT=system
      ;;
    deb13-nocc)
      IMAGE=debian:13 PKGS="$BASE_PKGS curl git"
      EXPECT_TS=off EXPECT_TS_REASON="no C compiler" EXPECT_GIT=system
      ;;
    deb13-bare)
      IMAGE=debian:13 PKGS="$BASE_PKGS wget"
      EXPECT_TS=off EXPECT_TS_REASON="no C compiler" EXPECT_GIT=apt
      ;;
    *)
      echo "unknown job: $1" >&2
      exit 2
      ;;
  esac
}

run_job() {
  local job=$1 log="$LOG_DIR/$1.log" mounts=()
  job_config "$job"
  echo "== $job ($IMAGE: $PKGS)"
  docker build -q --platform "$PLATFORM" -t "dotfiles-install-test:$job" \
    --build-arg BASE="$IMAGE" --build-arg PKGS="$PKGS" "$HERE" >/dev/null
  mounts=(-v "$REPO:/src:ro")
  if [ -n "$CACHE" ]; then
    mkdir -p "$CACHE"
    mounts+=(-v "$CACHE:/cache")
  fi
  if docker run --rm --platform "$PLATFORM" "${mounts[@]}" \
    -e EXPECT_TS="$EXPECT_TS" -e EXPECT_TS_REASON="$EXPECT_TS_REASON" -e EXPECT_GIT="$EXPECT_GIT" \
    "dotfiles-install-test:$job" bash /src/tests/install/in-container.sh >"$log" 2>&1; then
    echo "   PASS ($log)"
    return 0
  fi
  echo "   FAIL ($log):"
  grep '^FAIL' "$log" | sed 's/^/     /' || tail -n 20 "$log"
  return 1
}

main() {
  local list=("$@") failed=() job
  if [ $# -eq 0 ]; then list=(deb12 deb13 deb13-nocc deb13-bare); fi
  echo "logs: $LOG_DIR"
  for job in "${list[@]}"; do
    run_job "$job" || failed+=("$job")
  done
  if [ ${#failed[@]} -gt 0 ]; then
    echo "failed: ${failed[*]}"
    exit 1
  fi
  echo "all passed: ${list[*]}"
}

main "$@"
