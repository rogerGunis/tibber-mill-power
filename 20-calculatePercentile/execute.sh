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
    --day=*)
      setDay "${i/*=/}"
      shift
      ;;
    --percentile=*)
      setPercentile "${i/*=/}"
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
setPercentile() {
  PERCENTILE="${1}"
}

getPercentile() {
  echo "${PERCENTILE:-all}"
}

setTmp() {
  TMP="${1}"
}

getTmp() {
  echo "${TMP:-}"
}

setDay() {
  DAY="${1}"
}

getDay() {
  echo "${DAY:-}"
}

printUsageAndExit() {
  {
    IFS="" read -r -d '' usageText <<EOT
usage: ${SCRIPT_NAME} --tmp=.... temporary directory saving files
                      --day=[today|tomorrow]
                      --percentile=[all|50|60|70|80...|100]..... list all percentiles
  example:
     ./${SCRIPT_NAME} --tmp=/tmp/exchange --day=today
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

calculatePercentile() {
  local input="$(getTmp)/percentile.tmp"
  jq '.data.viewer.homes[0].currentSubscription.priceInfo.'$(getDay)'[].total' "$(getTmp)/data.json" | sort >"${input}"

  # get amount of values
  num="$(wc -l "${input}" | cut -f1 -d' ')"
  # sort values
  # print the desired percentiles
  for p in $(seq 0 5 100); do
    if [[ $p == 0 ]]; then continue; fi
    calcN=$(echo "$num / 100 * $p" | bc -l | awk -F\. '{print $1}')
    if [[ "$(getPercentile)" == "all" ]]; then
      printf "%3s%%: %-5.5s ct\n" "$p" "$(head "${input}" -n "${calcN}" | tail -n1)"
    elif [ "$(getPercentile)" == "${p}" ]; then
      echo "$(head "${input}" -n "${calcN}" | tail -n1)"
    fi
  done

}

checkDay() {
  return "$(getDay | grep -Eq "(today|tomorrow)"; echo $?)"
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

  if [[ $(checkDay) ]]; then
    error "day not allowed"
    printUsageAndExit
    exit 1
  fi

  calculatePercentile
}

main "$@"
