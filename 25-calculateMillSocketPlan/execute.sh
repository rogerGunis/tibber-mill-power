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

  # cleanup
#  rm -f "$(getTmp)/timer.json" "$(getTmp)/timerSorted.json"
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
    --percentile-price-today=*)
      setPercentilePriceToday "${i/*=/}"
      shift
      ;;
    --percentile-price-tomorrow=*)
      setPercentilePriceTomorrow "${i/*=/}"
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

printUsageAndExit() {
  {
    IFS="" read -r -d '' usageText <<EOT
usage: ${SCRIPT_NAME} --tmp=.... temporary directory saving files
                      --percentile-price=..... set percentile price value
  example:
     ./${SCRIPT_NAME} --tmp=/tmp/exchange
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

setPercentilePriceToday() {
  PERCENTILE_PRICE_TODAY="${1}"
}

getPercentilePriceToday() {
  echo "${PERCENTILE_PRICE_TODAY:-}"
}

setPercentilePriceTomorrow() {
  PERCENTILE_PRICE_TOMORROW="${1}"
}

getPercentilePriceTomorrow() {
  echo "${PERCENTILE_PRICE_TOMORROW:-}"
}

makePlan() {
  : >"$(getTmp)/timer.json"
  for DAY in "today" "tomorrow"; do
    sub=getPercentilePrice${DAY^}
    local percentilePrice
    percentilePrice=$(${sub})
    info "Percentile-Price ${DAY^}: ${percentilePrice}"

    if [[ -n "${percentilePrice}" ]];then
      jq '.data.viewer.homes[0].currentSubscription.priceInfo.'${DAY}'[] | select((.total <= '"${percentilePrice}"')) | (.startsAt = (.startsAt | strptime("%Y-%m-%dT%H:%M:%S.000+01:00") | mktime)) | (.startsAt = (.startsAt / 60)) | with_entries(if .key == "startsAt" then .key = "timestamp" else . end) | del(.total) | .name = "AlwaysHeating"' "$(getTmp)/data.json"  >>"$(getTmp)/timer.json"

      jq '.data.viewer.homes[0].currentSubscription.priceInfo.'${DAY}'[] | select((.total > '"${percentilePrice}"')) | (.startsAt = (.startsAt | strptime("%Y-%m-%dT%H:%M:%S.000+01:00") | mktime)) | (.startsAt = (.startsAt / 60)) | with_entries(if .key == "startsAt" then .key = "timestamp" else . end) | del(.total) | .name = "Off"' "$(getTmp)/data.json"  >>"$(getTmp)/timer.json"
    fi
  done

  : >"$(getTmp)/timerSorted.json"
  jq -s -c 'sort_by(.timestamp|tonumber)' "$(getTmp)/timer.json" | jq >>"$(getTmp)/timerSorted.json"

  : >"$(getTmp)/timerReduced.json"
  jq 'reduce .[] as $x (null; if . == null then [$x] elif .[-1].name == $x.name then .  else . + [$x] end)' "$(getTmp)/timerSorted.json" >>"$(getTmp)/timerReduced.json"

  : >"$(getTmp)/plan4mill.json"
  {
    echo '{"non_repeatable_timers":'
    cat "$(getTmp)/timerReduced.json"
    echo '}'
  } | jq >>"$(getTmp)/plan4mill.json"


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
  if [[ -z "$(getPercentilePriceToday)" ]]; then
    error "percentile today price empty"
    printUsageAndExit
    exit 1
  fi

  makePlan
}

main "$@"
