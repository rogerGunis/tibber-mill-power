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

LOG_LEVEL=LOG_LEVEL_INFO
EXAMPLE=""

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
    --host=*)
      setHost "${i/*=/}"
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
setHost() {
  HOST="${1}"
}

getHost() {
  echo "${HOST:-all}"
}

setToken() {
  TOKEN="${1}"
}

getToken() {
  echo "${TOKEN:-}"
}

setTmp() {
  TMP="${1}"
}

getTmp() {
  echo "${TMP:-}"
}

setHost() {
  HOST="${1}"
}

getHost() {
  echo "${HOST:-}"
}

printUsageAndExit() {
  {
    IFS="" read -r -d '' usageText <<EOT
usage: ${SCRIPT_NAME} --tmp=.... temporary directory saving files
                      --host=<ip>
                      --token=<token> ... if you have ssl enabled on mill socket
  example:
     ./${SCRIPT_NAME} --tmp=/tmp/exchange --host=fritz.box
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

getSchema() {
  local SCHEMA=http
  if [[ -n "$(getToken)" ]]; then
   SCHEMA=https
  fi
  echo "${SCHEMA}"
}

getHeader() {
  local HEADER
  if [[ -n "$(getToken)" ]]; then
    HEADER=("Authentication: $(getToken)")
  fi
  echo "${HEADER[@]/#/-H}"
}

getCurlOpts() {
  local CURL_OPT
  CURL_OPT=("-k")
  echo ${CURL_OPT[@]}
}

upload() {
  ping -q -c1 -w1 $(getHost) 1>/dev/null 2>&1 && ret=$? || ret=$?

  STATUS="failed"
  if [[ "${ret}" == "0" ]];then
    STATUS=$(curl $(getCurlOpts) -s -X POST "$(getHeader)" -H 'accept: */*' -d@"$(getTmp)/plan4mill.json" "$(getSchema)://$(getHost)/non-repeatable-timers" | jq .status | tr -d '"' || echo "failed")
  fi
  info "$(getHost) upload response: ${STATUS}"
}

validate() {
  > "$(getTmp)/plan4mill.validate.json"
  # curl -k -X GET  -H "Authentication: 1u1UvoVSG_yrU1gE"   -H 'accept: */*' https://192.168.116.138:443/non-repeatable-timers

  ping -q -c1 -w1 $(getHost) 1>/dev/null 2>&1 && ret=$? || ret=$?

  if [[ "${ret}" == "0" ]];then
    curl $(getCurlOpts) -o "$(getTmp)/plan4mill.validate.json" -s -X GET "$(getHeader)" -H 'accept: */*' "$(getSchema)://$(getHost)/non-repeatable-timers"
    echo "===================================="
    jq -r '[ .non_repeatable_timers[] | .time = (.time*60) | .time = (.time | todate) | .type_value = (.type_value | tostring | (length | if . <= 3 then " " * (13 - .) else "" end) as $padding | "\($padding)\(.)") ] | (map(keys) | add | unique) as $cols | map(. as $row | $cols | map($row[.])) as $rows | $cols, $rows[] | @tsv' "$(getTmp)/plan4mill.validate.json"
    echo "===================================="
  fi
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

  upload
  validate
}

main "$@"
