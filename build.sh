#!/bin/bash
# Based on the Icinga 2 Docker image build.bash
# Icinga 2 Docker image | (c) 2020 Icinga GmbH | GPLv2+
set -exo pipefail

ACTION="$1"
TAG="${2:-latest}"

if [ -z "$REPO_OWNER"]; then
    echo "Environment variable REPO_OWNER is not set. This should be set by the build system automatically. If you are running this manually, set it before running." >&2
    false
fi

if [ -z "$ACTION" ]; then
	cat <<EOF >&2
FATAL: You must specify an action to take
Usage: ${0} [build|push|local-build [TAG]]
EOF
	false
fi

# DEBUG
echo "Action is $ACTION"
echo "Tag is $TAG"

# Check if this is using nerdctl or docker for the build
if nerdctl version; then
    BUILDTOOL=nerdctl
elif docker buildx version; then
    BUILDTOOL="docker buildx"
else
    echo 'Neither nerdctl nor docker buildx are available.' >&2
    false
fi

# DEBUG
echo "Selected tool is: $BUILDTOOL"

WORKING_DIR="$(realpath "$(dirname "$0")")"
COMMON_ARGS=(--tag "ghcr.io/$REPO_OWNER/icinga2-custom:$TAG" $WORKING_DIR)
BUILD_CMD=($BUILDTOOL build --platform "$(cat platforms.txt)")

case "$ACTION" in
	build)
		"${BUILD_CMD[@]}" "${COMMON_ARGS[@]}"
		;;
	push)
		"${BUILD_CMD[@]}" --push "${COMMON_ARGS[@]}"
		;;
	local-build)
		"${BUILD_CMD[@]}" --load "${COMMON_ARGS[@]}"
		;;
esac
