#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/upgrade-mem.sh <version> [options]

Updates NowledgeMem to the given version, copies the matching mem image into
the LazyCat registry, updates lzc-manifest.yml, builds the LPK, and commits the
changed release files.

Options:
  --publish           Publish the LPK to LazyCat app store after build
  --push              Push git commit to remote (default if commit is created)
  --no-push           Skip git push
  --no-commit         Skip git commit
  --no-build          Skip LPK build
  --changelog <msg>   Changelog message for app store publish

Environment:
  SOURCE_IMAGE=<image>       Override source image. Default: nowledgelabs/mem:<version>-vulkan
  COMMIT_MESSAGE=<message>   Override git commit message.
  CHANGELOG=<message>        Changelog for app store publish.
  SKIP_COMMIT=1              Build without creating a git commit.
  SKIP_PUSH=1                Skip pushing to remote after commit.
  SKIP_BUILD=1               Update files and commit without running lzc-cli project build.
  PUBLISH=1                  Publish to LazyCat app store after build.
  COPY_IMAGE_OUTPUT=<text>   Use captured copy-image output instead of calling LazyCat.
                             Supports "uploaded:" and "lazycat-registry:" output.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

update_package_version() {
  local version=$1
  local tmp
  tmp=$(mktemp)

  awk -v version="$version" '
    BEGIN { updated = 0 }
    !updated && /^version:[[:space:]]*/ {
      print "version: " version
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "package.yml does not contain a top-level version field" > "/dev/stderr"
        exit 1
      }
    }
  ' package.yml >"$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" package.yml
}

copy_image() {
  local source_image=$1
  local output

  if [[ -n ${COPY_IMAGE_OUTPUT:-} ]]; then
    output=$COPY_IMAGE_OUTPUT
  else
    echo "Copying image: $source_image" >&2
    if command -v fish >/dev/null 2>&1 && fish -lc 'functions -q lzc-copy-image'; then
      if ! output=$(COPY_IMAGE="$source_image" fish -lc 'lzc-copy-image "$COPY_IMAGE"' 2>&1); then
        printf '%s\n' "$output" >&2
        return 1
      fi
    else
      need_cmd lzc-cli
      if ! output=$(lzc-cli appstore copy-image "$source_image" 2>&1); then
        printf '%s\n' "$output" >&2
        return 1
      fi
    fi
  fi

  printf '%s\n' "$output" >&2
  printf '%s\n' "$output" |
    grep -Eo 'registry\.lazycat\.cloud/[A-Za-z0-9._:@/-]+' |
    tail -n 1 || true
}

update_manifest_image() {
  local version=$1
  local image=$2
  local tmp
  tmp=$(mktemp)

  awk -v version="$version" -v image="$image" '
    BEGIN {
      in_mem = 0
      updated_comment = 0
      updated_image = 0
    }
    /^  mem:[[:space:]]*$/ {
      in_mem = 1
      print
      next
    }
    in_mem && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
      in_mem = 0
    }
    in_mem && /^    #[[:space:]]*nowledgelabs\/mem:/ {
      print "    # nowledgelabs/mem:" version "-vulkan"
      updated_comment = 1
      next
    }
    in_mem && /^    image:[[:space:]]*/ {
      print "    image: " image
      updated_image = 1
      next
    }
    { print }
    END {
      if (!updated_comment) {
        print "lzc-manifest.yml mem service image comment was not found" > "/dev/stderr"
        exit 1
      }
      if (!updated_image) {
        print "lzc-manifest.yml mem service image field was not found" > "/dev/stderr"
        exit 1
      }
    }
  ' lzc-manifest.yml >"$tmp" || {
    rm -f "$tmp"
    return 1
  }

  mv "$tmp" lzc-manifest.yml
}

package_id() {
  awk -F':[[:space:]]*' '/^package:[[:space:]]*/ { gsub(/"/, "", $2); print $2; exit }' package.yml
}

build_lpk() {
  need_cmd lzc-cli
  echo "Building LPK..." >&2
  lzc-cli project build -f lzc-build.yml
}

commit_release() {
  local version=$1
  local lpk=$2
  local message=${COMMIT_MESSAGE:-"更新 NowledgeMem 到 ${version}"}

  need_cmd git
  git add package.yml lzc-manifest.yml "$lpk"

  if git diff --cached --quiet; then
    echo "No staged release changes; skipping commit." >&2
    return 0
  fi

  git commit -m "$message"
}

push_release() {
  local current_branch
  current_branch=$(git branch --show-current)
  echo "Pushing to origin/${current_branch}..." >&2
  git push origin "$current_branch"
  echo "Push completed." >&2
}

publish_lpk() {
  local lpk=$1
  local changelog=${CHANGELOG:-""}

  need_cmd lzc-cli

  if [[ ! -f "$lpk" ]]; then
    die "LPK file not found: $lpk"
  fi

  if [[ -z "$changelog" ]]; then
    changelog="更新到 $(awk '/^version:/ {print $2}' package.yml)"
  fi

  echo "Publishing to LazyCat app store..." >&2
  echo "  LPK: $lpk" >&2
  echo "  Changelog: $changelog" >&2
  lzc-cli appstore publish "$lpk" --changelog "$changelog" --clang zh
  echo "Publish completed." >&2
}

main() {
  if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
    exit 0
  fi

  local version=""
  local do_publish=${PUBLISH:-0}
  local do_push=${SKIP_PUSH:-0}
  local do_commit=${SKIP_COMMIT:-0}
  local do_build=${SKIP_BUILD:-0}
  local changelog=${CHANGELOG:-""}

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --publish)
        do_publish=1
        shift
        ;;
      --push)
        do_push=0
        shift
        ;;
      --no-push)
        do_push=1
        shift
        ;;
      --no-commit)
        do_commit=1
        shift
        ;;
      --no-build)
        do_build=1
        shift
        ;;
      --changelog)
        changelog="$2"
        shift 2
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        if [[ -z "$version" ]]; then
          version="$1"
        else
          die "unexpected argument: $1"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$version" ]] || {
    usage >&2
    exit 1
  }
  [[ "$version" != *[[:space:]]* ]] || die "version must not contain whitespace"

  need_cmd awk
  need_cmd grep
  need_cmd tail
  need_cmd mktemp

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  cd "$repo_root"

  [[ -f package.yml ]] || die "package.yml not found"
  [[ -f lzc-manifest.yml ]] || die "lzc-manifest.yml not found"
  [[ -f lzc-build.yml ]] || die "lzc-build.yml not found"

  local source_image=${SOURCE_IMAGE:-"nowledgelabs/mem:${version}-vulkan"}
  update_package_version "$version"

  local lazycat_image
  lazycat_image=$(copy_image "$source_image")
  [[ -n "$lazycat_image" ]] || die "failed to parse LazyCat registry image from copy-image output"
  update_manifest_image "$version" "$lazycat_image"

  local pkg
  pkg=$(package_id)
  [[ -n "$pkg" ]] || die "failed to parse package id from package.yml"
  local lpk="${pkg}-v${version}.lpk"

  if [[ $do_build != "1" ]]; then
    build_lpk
    [[ -f "$lpk" ]] || die "expected build output not found: $lpk"
  fi

  if [[ $do_commit != "1" ]]; then
    [[ -f "$lpk" ]] || die "cannot commit missing LPK: $lpk"
    commit_release "$version" "$lpk"
  fi

  # Push to remote (default after commit, unless --no-push)
  if [[ $do_push != "1" ]]; then
    push_release
  fi

  # Publish to app store
  if [[ $do_publish == "1" ]]; then
    publish_lpk "$lpk" "$changelog"
  fi

  echo ""
  echo "=== Release ${version} completed ==="
  echo "  package.yml     - version updated"
  echo "  lzc-manifest.yml - image updated"
  echo "  ${lpk}          - built"
  [[ $do_commit != "1" ]] && echo "  git commit      - created"
  [[ $do_push != "1" ]]   && echo "  git push        - pushed to remote"
  [[ $do_publish == "1" ]] && echo "  app store       - published"
}

export CHANGELOG="${CHANGELOG:-}"
main "$@"
