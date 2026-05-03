#!/bin/bash
set -e

REQUIRED_PACKAGES=(
  saunafs-master
  saunafs-metalogger
  saunafs-cgiserv
  saunafs-chunkserver
  saunafs-client
  saunafs-adm
)

usage() {
  echo "Usage: $0 [--saunafs-version <version>] --distro <distro> [--registry <registry>] [--project <project>] [--branch <branch>]"
  echo "If --registry is not provided, defaults to saywish-mini-al:443"
  echo "If --project is not provided, defaults to leilfs"
  echo "If --branch is not provided, the current git branch is used"
  echo "If --saunafs-version is not provided, the script will query repo.leil.io and ask you to choose"
  echo "Example: $0 --saunafs-version 5.8.0-1 --distro 24.04 --registry saywish-mini-al:443 --project leilfs"
  exit 1
}

get_codename() {
  case "$1" in
    22.04) echo "jammy" ;;
    24.04) echo "noble" ;;
    *)
      echo "Unsupported distro: $1" >&2
      echo "This repository currently supports only 22.04 and 24.04." >&2
      exit 1
      ;;
  esac
}

print_available_versions() {
  local versions=("$@")
  local version

  echo "Available LeilFS versions for Ubuntu $DISTRO:"
  for version in "${versions[@]}"; do
    echo "  - $version"
  done
}

fetch_available_versions() {
  local codename="$1"
  local repo_url="https://repo.leil.io/repository/saunafs-ubuntu-$DISTRO/dists/$codename/main/binary-amd64/Packages.gz"
  local package_regex

  package_regex="$(printf "%s|" "${REQUIRED_PACKAGES[@]}")"
  package_regex="${package_regex%|}"

  mapfile -t AVAILABLE_VERSIONS < <(
    curl -fsSL "$repo_url" \
      | gzip -dc \
      | awk -v package_regex="$package_regex" -v expected_count="${#REQUIRED_PACKAGES[@]}" '
          BEGIN {
            RS = ""
            split(package_regex, package_list, "|")
            for (i in package_list) {
              required[package_list[i]] = 1
            }
          }
          {
            pkg = ""
            ver = ""
            n = split($0, lines, "\n")
            for (i = 1; i <= n; i++) {
              if (lines[i] ~ /^Package: /) {
                pkg = substr(lines[i], 10)
              } else if (lines[i] ~ /^Version: /) {
                ver = substr(lines[i], 10)
              }
            }
            if (pkg in required && ver != "") {
              key = ver SUBSEP pkg
              if (!(key in seen)) {
                seen[key] = 1
                counts[ver]++
              }
            }
          }
          END {
            for (ver in counts) {
              if (counts[ver] == expected_count) {
                print ver
              }
            }
          }
        ' \
      | sort -r -V
  )

  if [[ "${#AVAILABLE_VERSIONS[@]}" -eq 0 ]]; then
    echo "Failed to determine available LeilFS versions from $repo_url" >&2
    exit 1
  fi
}

ensure_valid_version() {
  local requested_version="$1"
  local version

  for version in "${AVAILABLE_VERSIONS[@]}"; do
    if [[ "$version" == "$requested_version" ]]; then
      return 0
    fi
  done

  echo "Requested LeilFS version '$requested_version' is not available for Ubuntu $DISTRO." >&2
  print_available_versions "${AVAILABLE_VERSIONS[@]}" >&2
  exit 1
}

choose_version_interactively() {
  if [[ ! -t 0 ]]; then
    echo "No --saunafs-version provided and no interactive terminal is available." >&2
    print_available_versions "${AVAILABLE_VERSIONS[@]}" >&2
    exit 1
  fi

  print_available_versions "${AVAILABLE_VERSIONS[@]}"
  echo
  echo "Select the LeilFS version to build:"

  PS3="Enter selection number: "
  select selected_version in "${AVAILABLE_VERSIONS[@]}"; do
    if [[ -n "$selected_version" ]]; then
      SAUNAFS_VERSION="$selected_version"
      break
    fi
    echo "Invalid selection."
  done
}

# Default Harbor target
REGISTRY="saywish-mini-al:443"
PROJECT="leilfs"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --saunafs-version)
      SAUNAFS_VERSION="$2"
      shift 2
      ;;
    --distro)
      DISTRO="$2"
      shift 2
      ;;
    --registry)
      REGISTRY="$2"
      shift 2
      ;;
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$DISTRO" ]]; then
  usage
fi

if [[ "$REGISTRY" != *.* && "$REGISTRY" != *:* && "$REGISTRY" != "localhost" ]]; then
  echo "Registry '$REGISTRY' looks like a bare hostname."
  echo "Docker will interpret that as Docker Hub, not your Harbor registry."
  echo "Use a registry value like 'saywish-mini-al:443' or another hostname containing a dot."
  exit 1
fi

CODENAME="$(get_codename "$DISTRO")"
fetch_available_versions "$CODENAME"

if [[ -z "$SAUNAFS_VERSION" ]]; then
  choose_version_interactively
else
  ensure_valid_version "$SAUNAFS_VERSION"
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="detached"
fi

TAG_SUFFIX="ubuntu-$DISTRO"
BASE_IMAGE="saunafs-base:$TAG_SUFFIX"
REMOTE_BASE_IMAGE="$REGISTRY/$PROJECT/saunafs-base:$TAG_SUFFIX"
REMOTE_TAG="ubuntu-$DISTRO-leilfs-$SAUNAFS_VERSION-$BRANCH"
COMPONENTS=(master metalogger cgiserver chunkserver client)

# Identify running containers that will be affected by this publication
echo "Searching for running containers using Saunafs $SAUNAFS_VERSION on Ubuntu $DISTRO..."
# We look for containers using images with both the version and distro in their tag/image name
# Supporting both "distro-version" and "version-distro" formats
MAP_VERSION_DISTRO=".*$SAUNAFS_VERSION.*$DISTRO.*|.*$DISTRO.*$SAUNAFS_VERSION.*"
# We use docker inspect to check the original Config.Image name, which persists even if the local tag is deleted
AFFECTED_CONTAINERS=$(docker ps -q | xargs -I {} docker inspect {} --format '{{.Image}} {{.Config.Image}} {{.Name}}' | grep -E "$MAP_VERSION_DISTRO" | awk '{print $NF}' | sed 's/^\///' || true)

if [[ -n "$AFFECTED_CONTAINERS" ]]; then
  echo "WARNING: The following containers are using images related to Saunafs $SAUNAFS_VERSION and Ubuntu $DISTRO:"
  echo "$AFFECTED_CONTAINERS"
  echo
  echo "These containers should be stopped to ensure a clean deployment."
  echo "press ENTER to continue..."
  read 
  if [[ -t 0 ]]; then
    read -p "Do you want to stop these containers now? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "Stopping and removing affected containers..."
      docker rm -f $AFFECTED_CONTAINERS
    else
      echo "Proceeding without removing containers. Note that this might lead to stale cache or naming conflicts."
    fi
  else
    echo "Non-interactive shell detected. Automatically removing affected containers..."
    docker rm -f $AFFECTED_CONTAINERS
  fi
fi

# Cleanup old local builds to ensure a fresh start
echo "Cleaning up old local images for a clean rebuild..."
for component in "${COMPONENTS[@]}"; do
  docker rmi "saunafs-$component:$SAUNAFS_VERSION-$TAG_SUFFIX" 2>/dev/null || true
done
docker rmi "$BASE_IMAGE" 2>/dev/null || true

# Docker login if credentials are present
if [[ -n "$DOCKER_USER" && -n "$DOCKER_PASS" ]]; then
  printf "%s\n" "$DOCKER_PASS" | docker login "$REGISTRY" -u "$DOCKER_USER" --password-stdin
fi

# 1. Build base image

echo "Building base image: $BASE_IMAGE"
docker build -t "$BASE_IMAGE" --build-arg BASE_IMAGE="ubuntu:$DISTRO" ./saunafs-base
echo "Tagging $BASE_IMAGE as $REMOTE_BASE_IMAGE"
docker tag "$BASE_IMAGE" "$REMOTE_BASE_IMAGE"
echo "Pushing $REMOTE_BASE_IMAGE"
docker push "$REMOTE_BASE_IMAGE"

# 2. Build and tag all component images

echo "Building all component images with LeilFS version $SAUNAFS_VERSION and distro $DISTRO"
SAUNAFS_VERSION="$SAUNAFS_VERSION" TAG_SUFFIX="$TAG_SUFFIX" BASE_IMAGE="$BASE_IMAGE" docker compose build


# 3. Push all images to your registry
for component in "${COMPONENTS[@]}"; do
  IMAGE="saunafs-$component:$SAUNAFS_VERSION-$TAG_SUFFIX"
  REMOTE_IMAGE="$REGISTRY/$PROJECT/saunafs-$component:$REMOTE_TAG"
  echo "Tagging $IMAGE as $REMOTE_IMAGE"
  docker tag "$IMAGE" "$REMOTE_IMAGE"
  echo "Pushing $REMOTE_IMAGE"
  docker push "$REMOTE_IMAGE"
  echo "Removing local image $REMOTE_IMAGE to prevent stale cache"
  docker rmi "$REMOTE_IMAGE" || true
done

echo "Removing local base image $REMOTE_BASE_IMAGE to prevent stale cache"
docker rmi "$REMOTE_BASE_IMAGE" || true

echo "Done."
