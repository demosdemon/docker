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
	pyenv
	tox-base
	tox
	circleci-tox
)

_travis() {
	if [[ $TRAVIS == "true" ]]; then
		printf 'travis_fold:%s:%s\n' "$1" "$2"
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

	from=$(grep '^FROM' "docker-${build_image}/Dockerfile" | cut -d ' ' -f2)
	_log "Pulling base image $from..."
	_exec docker pull "$from"

	_log "Pulling $latest_image..."
	_exec docker pull "$latest_image"

	_log "Building $image..."
	_exec docker build --cache-from "$latest_image" -t "$image" "docker-${build_image}"

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
