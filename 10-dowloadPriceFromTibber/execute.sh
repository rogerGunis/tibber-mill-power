#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Catch line number trace function which called error
set -eE -o functrace

# remove echoing directory name on 'cd' command
unset CDPATH
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # the full path of the directory where the script resides
readonly SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")" # full path including script name
readonly SCRIPT_NAME="$(basename "${SCRIPT_PATH}" .sh)"              # script name without path and also without file extension
readonly HOST_NAME=$(hostname)
readonly LOG_PREFIX='echo "# [${HOST_NAME}:${SCRIPT_NAME} $(date +'"'"'%Y-%m-%d %H:%M:%S'"'"')]"'
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3
readonly TIBBER_API_URI="https://api.tibber.com/v1-beta/gql"

LOG_LEVEL=LOG_LEVEL_INFO
TMP=""

debug() {
  ((LOG_LEVEL >= LOG_LEVEL_DEBUG)) && echo >&2 -e "$(eval "${LOG_PREFIX}") DEBUG: ${*}" || true
}

info() {
  ((LOG_LEVEL >= LOG_LEVEL_INFO)) && echo >&2 -e "$(eval "${LOG_PREFIX}") \e[32mINFO: \e[39m ${*}" || true
}

warn() {
  ((LOG_LEVEL >= LOG_LEVEL_WARN)) && echo >&2 -e "$(eval "${LOG_PREFIX}") \e[33mWARN: \e[39m ${*}" || true
}

error() {
  ((LOG_LEVEL >= LOG_LEVEL_ERROR)) && echo >&2 -e "$(eval "${LOG_PREFIX}") \e[31mERROR:\e[39m ${*}" || true
}

onExit() {
  local errorCode=$1
  local lineno=$2
  # your cleanup code here ...
  if [[ $errorCode -gt 0 ]]; then
    info "Exiting with errors <$errorCode>, lineNumber <$lineno>"
  fi
}

#exit traps in any case, also in case of ERR
trap 'onExit $? ${LINENO}' EXIT

parseArguments() {
  for i in "$@"; do
    case $i in
    --tmp=*)
      setTmp "${i/*=/}"
      shift
      ;;
    --token=*)
      setToken "${i/*=/}"
      shift
      ;;
    --help | -h)
      printUsageAndExit
      ;;
    *)
      error "Unknown option: ${i}"
      printUsageAndExit
      ;;
    esac
  done
}

setTmp() {
  TMP="${1}"
}

getTmp() {
  echo "${TMP:-}"
}

setToken() {
  TOKEN="${1}"
}

getToken() {
  echo "${TOKEN:-}"
}

savePriceDataFromTibber() {
  if curl \
    -s \
    -H "Authorization: Bearer $(getToken)" \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{ "query": "{viewer{homes{currentSubscription{priceInfo{today{startsAt total} tomorrow{startsAt total}}}}}}"}' \
    ${TIBBER_API_URI} >"$(getTmp)/data.json"; then
    info "Downloaded file in $(getTmp)/data.json"
  else
    error "Download failed"
    exit 1
  fi
}

printUsageAndExit() {
  {
    IFS="" read -r -d '' usageText <<EOT
usage: ${SCRIPT_NAME} --tmp=.... temporary directory saving files
                      --tibber=... token for the tibber api
  example:
     ./${SCRIPT_NAME} --tmp=/tmp/exchange --tibber=YSD-4711
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

main() {
  # info "SCRIPT_DIR is ${SCRIPT_DIR}"
  # info "SCRIPT_PATH is ${SCRIPT_PATH}"
  # info "SCRIPT_NAME is ${SCRIPT_NAME}"
  # info "BASH_SOURCE is ${BASH_SOURCE[@]}"
  parseArguments "$@"
  if [[ ! -d "$(getTmp)" ]]; then
    error "tmp directory not existing"
    printUsageAndExit
    exit 1
  fi
  if [[ -z "$(getToken)" ]]; then
    error "tibber token empty"
    printUsageAndExit
    exit 1
  fi

  savePriceDataFromTibber
}

main "$@"
