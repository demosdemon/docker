#!/usr/bin/env bash

set -e

# for timestamps
export TZ="${TZ:-America/Chicago}"

if [[ "$CI" ]]; then
	declare -x
else
	if [[ -z $DOCKER_USERNAME ]]; then
		DOCKER_USERNAME=demosdemon
	fi
fi

declare -a build_images=(
	gbp
	pyenv
	tox-base
	tox
	circleci-tox
)

_travis() {
	if [[ $TRAVIS == "true" ]]; then
		printf 'travis_fold:%s:%s\r\e[0K' "$1" "$2"
	fi
}

_echo() {
	local -r level="$1"
	shift

	printf -- "$(date +%c) ${level}: %s\n" "$@"
}

_warn() {
	_echo "WARN" "$@" >&2
}

_log() {
	_echo "INFO" "$@" >&2
}

_exec() {
	_log "exec: $*"
	"$@"
}

if [[ -z $DOCKER_USERNAME ]]; then
	_warn '$DOCKER_USERNAME not set!'
	exit 1
fi

for build_image in "${build_images[@]}"; do
	_travis start "$build_image"
	latest_image="${DOCKER_USERNAME}/${build_image}:latest"
	image="${DOCKER_USERNAME}/${build_image}:${TRAVIS_BUILD_NUMBER:-0}"

	_log "Pulling $latest_image for cache"
	if ! _exec docker pull "$latest_image"; then
		_warn "Unable to pull latest image. Docker will rebuild image from scratch."
	fi

	_log "Building $image..."
	_exec docker build --pull --cache-from "$latest_image" -t "$image" "images/${build_image}"

	if [[ -n $DOCKER_PASSWORD ]]; then
		_log "Uploading $image"
		_exec docker push "$image"

		if [[ $TRAVIS_BRANCH == "master" ]]; then
			_log "Uploading $latest_image"
			_exec docker tag "$image" "$latest_image"
			_exec docker push "$latest_image"
		else
			_warn "Not on master, not pushing latest tag."
		fi
	else
		_warn '$DOCKER_PASSWORD not set, not uploading images.'
	fi
	_travis end "$build_image"
done

_travis start thumbor
cd ./images/thumbor
IMAGE_PREFIX=$DOCKER_USERNAME ./build
if [[ -n $DOCKER_PASSWORD ]]; then
	IMAGE_PREFIX=$DOCKER_USERNAME ./push "$TRAVIS_BRANCH";
fi
_travis end thumbor
