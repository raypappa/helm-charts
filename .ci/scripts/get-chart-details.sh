#!/usr/bin/env bash
#
# Adapted from bjw-s-labs/helm-charts @ f18861fb
#   .ci/scripts/get-chart-details.sh
# Copyright 2025 Bernd Schorgers
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# get-chart-details.sh — read Chart.yaml, validate name/version/type,
# optionally require the artifacthub.io/changes annotation, and write
# the chart's name, version, type, and changes list to GITHUB_OUTPUT
# (or to a caller-supplied --output-file).
#
# Usage:
#   get-chart-details.sh CHART_PATH [options]
#   get-chart-details.sh --path CHART_PATH [options]
#
# Options:
#   --allowChartToNotExist    Do not fail if the chart directory is missing.
#                            The script exits 0 with a warning in that case.
#   --validateChartYaml      Require Chart.yaml to have a non-empty name,
#                            version, and a type of application or library.
#   --requireChangelog       Require a non-empty
#                            annotations."artifacthub.io/changes" list with
#                            at least one entry. Each entry must have a kind
#                            in {added, changed, deprecated, removed, fixed,
#                            security} and a non-empty description. Optional
#                            links[] must be objects with name and a valid URL.
#   --output-file PATH       Write outputs to PATH instead of stdout
#                            (or $GITHUB_OUTPUT when set).

set -euo pipefail

usage() {
  printf 'Usage: %s CHART_PATH|--path PATH [--allowChartToNotExist] [--validateChartYaml] [--requireChangelog] [--output-file PATH]\n' "$0" >&2
}

chart_path=''
allow_missing=false
validate_chart=false
require_changelog=false
output_file="${GITHUB_OUTPUT:-}"

while (($# > 0)); do
  case "$1" in
    --path)
      (($# >= 2)) || { usage; exit 2; }
      [[ -z "$chart_path" ]] || { usage; exit 2; }
      chart_path=$2
      shift 2
      ;;
    --allowChartToNotExist) allow_missing=true; shift ;;
    --validateChartYaml) validate_chart=true; shift ;;
    --requireChangelog) require_changelog=true; shift ;;
    --output-file)
      (($# >= 2)) || { usage; exit 2; }
      output_file=$2
      shift 2
      ;;
    --) shift; (($# == 0)) || { usage; exit 2; } ;;
    -*) usage; exit 2 ;;
    *)
      [[ -z "$chart_path" ]] || { usage; exit 2; }
      chart_path=$1
      shift
      ;;
  esac
done

[[ -n "$chart_path" ]] || { usage; exit 2; }
chart_yaml="$chart_path/Chart.yaml"
if [[ ! -f "$chart_yaml" ]]; then
  if [[ "$allow_missing" == true && ! -e "$chart_path" ]]; then
    printf 'Warning: chart does not exist: %s\n' "$chart_path" >&2
    exit 0
  fi
  printf 'Chart details: Chart.yaml not found at %s. Provide a chart path containing Chart.yaml.\n' "$chart_path" >&2
  exit 1
fi

if ! yq eval '.' "$chart_yaml" >/dev/null; then
  printf 'Chart details: Chart.yaml at %s is not valid YAML. Fix the chart metadata file.\n' "$chart_path" >&2
  exit 1
fi

name=$(yq -r '.name // ""' "$chart_yaml")
version=$(yq -r '.version // ""' "$chart_yaml")
type=$(yq -r '.type // "application"' "$chart_yaml")

if [[ "$validate_chart" == true ]]; then
  if [[ -z "$name" || -z "$version" ]]; then
    printf "Chart '%s': name and version must be nonempty in Chart.yaml. Set both metadata fields.\n" "$chart_path" >&2
    exit 1
  fi
  if [[ "$type" != application && "$type" != library ]]; then
    printf "Chart '%s': type must be application or library. Set Chart.yaml 'type' accordingly.\n" "$chart_path" >&2
    exit 1
  fi
fi

changes=''
if [[ "$require_changelog" == true ]]; then
  changes_yaml=$(yq -r '.annotations."artifacthub.io/changes" // ""' "$chart_yaml")
  if [[ -z "$changes_yaml" ]]; then
    printf "Chart '%s': artifacthub.io/changes annotation is required and must contain entries. Add a valid changelog annotation to Chart.yaml.\n" "$chart_path" >&2
    exit 1
  fi

  changes_file=$(mktemp)
  trap 'rm -f "$changes_file"' EXIT
  printf '%s\n' "$changes_yaml" >"$changes_file"
  if ! yq eval '.' "$changes_file" >/dev/null 2>&1 || ! yq -e 'type == "!!seq" and length > 0' "$changes_file" >/dev/null; then
    printf "Chart '%s': artifacthub.io/changes must be a nonempty YAML list. Use list entries with kind and description.\n" "$chart_path" >&2
    exit 1
  fi

  entry_count=$(yq -r 'length' "$changes_file")
  for ((i = 0; i < entry_count; i++)); do
    kind=$(yq -r ".[$i].kind // \"\"" "$changes_file")
    description=$(yq -r ".[$i].description // \"\"" "$changes_file")
    case "$kind" in
      added|changed|deprecated|removed|fixed|security) ;;
      *)
        printf "Chart '%s': changelog entry %d has an invalid kind. Use added, changed, deprecated, removed, fixed, or security.\n" "$chart_path" "$((i + 1))" >&2
        exit 1
        ;;
    esac
    [[ -n "$description" ]] || {
      printf "Chart '%s': changelog entry %d must have a nonempty description. Add a description to the entry.\n" "$chart_path" "$((i + 1))" >&2
      exit 1
    }

    if yq -e ".[$i] | has(\"links\")" "$changes_file" >/dev/null 2>&1; then
      yq -e ".[$i].links | type == \"!!seq\"" "$changes_file" >/dev/null || {
        printf "Chart '%s': changelog entry %d links must be a list of name/url objects. Fix the links field.\n" "$chart_path" "$((i + 1))" >&2
        exit 1
      }
      link_count=$(yq -r ".[$i].links | length" "$changes_file")
      for ((j = 0; j < link_count; j++)); do
        link_name=$(yq -r ".[$i].links[$j].name // \"\"" "$changes_file")
        link_url=$(yq -r ".[$i].links[$j].url // \"\"" "$changes_file")
        [[ -n "$link_name" && -n "$link_url" && "$link_url" =~ ^[A-Za-z][A-Za-z0-9+.-]*:[^[:space:]]+$ ]] || {
          printf "Chart '%s': changelog entry %d link %d must have a nonempty name and valid URL. Fix the link object.\n" "$chart_path" "$((i + 1))" "$((j + 1))" >&2
          exit 1
        }
      done
    fi
  done
  changes=$(yq -o=json -I=0 '.' "$changes_file")
fi

write_output() {
  local key=$1 value=$2
  if [[ -n "$output_file" ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$output_file"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

write_output name "$name"
write_output version "$version"
write_output type "$type"
write_output changes "$changes"
