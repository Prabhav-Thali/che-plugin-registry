#!/bin/bash
#
# Copyright (c) 2018-2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#

set -e

REGISTRY="quay.io"
ORGANIZATION="prabhav"
TAG="nightly"
DOCKERFILE="./build/dockerfiles/Dockerfile"
BUILD_FLAGS=""
SKIP_OCI_IMAGE="false"
NODE_BUILD_OPTIONS="${NODE_BUILD_OPTIONS:-}"
BUILDX="false"
PLATFORM=""
PR_CHECK="false"

USAGE="
Usage: ./build.sh [OPTIONS]
Options:
    --help
        Print this message.
    --tag, -t [TAG]
        Docker image tag to be used for image; default: 'nightly'
    --registry, -r [REGISTRY]
        Docker registry to be used for image; default 'quay.io'
    --organization, -o [ORGANIZATION]
        Docker image organization to be used for image; default: 'eclipse'
    --offline
        Build offline version of registry, with all artifacts included
        cached in the registry; disabled by default.
    --rhel
        Build using the rhel.Dockerfile (UBI images) instead of default
    --skip-oci-image
        Build artifacts but do not create the image
    --buildx
        Build using buildx in GH actions
    --platform
        Pass platform on image is to be built using GH actions
    --pr-check
        Build image using --load flag
"

function print_usage() {
    echo -e "$USAGE"
}

function parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -t|--tag)
            TAG="$2"
            shift; shift;
            ;;
            -r|--registry)
            REGISTRY="$2"
            shift; shift;
            ;;
            -o|--organization)
            ORGANIZATION="$2"
            shift; shift;
            ;;
            --offline)
            BUILD_FLAGS="--embed-vsix:true"
            shift;
            ;;
            --skip-oci-image)
            SKIP_OCI_IMAGE="true"
            shift;
            ;;
            --rhel)
            DOCKERFILE="./build/dockerfiles/rhel.Dockerfile"
            shift;
            ;;
            --buildx)
            BUILDX="true"
            shift;
            ;;
            -p|--platform)
            PLATFORM=$2
            shift; shift;
            ;;
            --pr-check)
            PR_CHECK="true"
            shift
            ;;
            *)
            print_usage
            exit 0
        esac
    done
}

parse_arguments "$@"

echo "Update yarn dependencies..."
yarn
echo "Build tooling..."
yarn --cwd "$(pwd)/tools/build" build
echo "Generate artifacts..."
eval node "${NODE_BUILD_OPTIONS}" tools/build/lib/entrypoint.js --output-folder:"$(pwd)/output" ${BUILD_FLAGS}

if [ "${SKIP_OCI_IMAGE}" != "true" ]; then
    BUILD_COMMAND="build"
    if [[ -z $BUILDER ]]; then
        echo "BUILDER not specified, trying with podman"
        BUILDER=$(command -v podman || true)
        if [[ ! -x $BUILDER ]]; then
            echo "[WARNING] podman is not installed, trying with buildah"
            BUILDER=$(command -v buildah || true)
            if [[ ! -x $BUILDER ]]; then
                echo "[WARNING] buildah is not installed, trying with docker"
                BUILDER=$(command -v docker || true)
                if [[ ! -x $BUILDER ]]; then
                    echo "[ERROR] neither docker, buildah, nor podman are installed. Aborting"; exit 1
                fi
            else
                BUILD_COMMAND="bud"
            fi
        fi
    else
        if [[ ! -x $(command -v "$BUILDER" || true) ]]; then
            echo "Builder $BUILDER is missing. Aborting."; exit 1
        fi
        if [[ $BUILDER =~ "docker" || $BUILDER =~ "podman" ]]; then
            if [[ ! $($BUILDER ps) ]]; then
                echo "Builder $BUILDER is not functioning. Aborting."; exit 1
            fi
        fi
        if [[ $BUILDER =~ "buildah" ]]; then
            BUILD_COMMAND="bud"
        fi
    fi

    if [[ "${BUILDX}" != "true" ]]; then
        echo "Building with $BUILDER buildx"
        IMAGE="${REGISTRY}/${ORGANIZATION}/che-plugin-registry:${TAG}"
        VERSION=$(head -n 1 VERSION)
        echo "Building che plugin registry ${VERSION}."
        ${BUILDER} ${BUILD_COMMAND} -t "${IMAGE}" -f "${DOCKERFILE}" .
    else
        if [[ $PR_CHECK != "true" ]]; then
            echo "Building with $BUILDER buildx"
            IMAGE="${REGISTRY}/${ORGANIZATION}/che-plugin-registry:${TAG}-$PLATFORM"
            VERSION=$(head -n 1 VERSION)
            echo "Building che plugin registry ${VERSION}."
            ${BUILDER} buildx ${BUILD_COMMAND} -t "${IMAGE}" --platform "$PLATFORM" -f "${DOCKERFILE}" --push .
        else 
            echo "Building with $BUILDER buildx"
            IMAGE="${REGISTRY}/${ORGANIZATION}/che-plugin-registry:${TAG}-$PLATFORM"
            VERSION=$(head -n 1 VERSION)
            echo "Building che plugin registry ${VERSION}."
            ${BUILDER} buildx ${BUILD_COMMAND} -t "${IMAGE}" --platform "$PLATFORM" -f "${DOCKERFILE}" --load .
        fi
    fi
fi
