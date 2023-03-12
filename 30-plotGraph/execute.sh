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
    --percentile-price=*)
      setPercentilePrice "${i/*=/}"
      shift
      ;;
    --percentile=*)
      setPercentile "${i/*=/}"
      shift
      ;;
    --day=*)
      setDay "${i/*=/}"
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

setDay() {
  DAY="${1}"
}

getDay() {
  echo "${DAY:-}"
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
                      --percentile=[50|60|70|80...|100].....
                      --percentile-price=..... set percentile price value - shown as dashed line
  example:
     ./${SCRIPT_NAME} --tmp=/tmp/exchange
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

setPercentilePrice() {
  PERCENTILE_PRICE="${1}"
}

getPercentilePrice() {
  echo "${PERCENTILE_PRICE:-}"
}

setPercentile() {
  PERCENTILE="${1}"
}

getPercentile() {
  echo "${PERCENTILE:-all}"
}

convertData() {
  # Prepare csv file with today's prices
  jq <$(getTmp)/data.json -r '.data.viewer.homes[0].currentSubscription.priceInfo.today[] | [.startsAt[11:19], .total] | @csv' >"$(getTmp)/today.dat"
  # Duplicate last data point so it is drawn
  tail -n1 $(getTmp)/today.dat | sed -e 's/00/59/' >>"$(getTmp)/today.dat"

  # Prepare csv file with tomorrow's prices
  jq <$(getTmp)/data.json -r '.data.viewer.homes[0].currentSubscription.priceInfo.tomorrow[] | [.startsAt[11:19], .total] | @csv' >"$(getTmp)/tomorrow.dat"
  # Duplicate last data point so it is drawn
  tail -n1 $(getTmp)/tomorrow.dat | sed -e 's/00/59/' >>"$(getTmp)/tomorrow.dat"
}

setLines() {
  local DAY_TITLE=$(jq '.data.viewer.homes[0].currentSubscription.priceInfo.today[] | .startsAt[0:10] ' $(getTmp)/data.json | sort -u | tr -d '"')
  # Prepare vertical line plot of current time
  local NOW=$(date +%H:%M)
  echo "set arrow from '${NOW}', graph 0 to '${NOW}', graph 1 nohead lt 0" >"$(getTmp)/nowline.gp"
  echo "set title 'Data from: ${DAY_TITLE}'" >> "$(getTmp)/nowline.gp"
  echo "set arrow from graph 0,first "$(getPercentilePrice)" to graph 1, first "$(getPercentilePrice)"nohead front lc rgb \"black\" lw 4  dashtype \"-\"" >>"$(getTmp)/nowline.gp"
  echo "set label '"$(getPercentile)"%' at 0,"$(getPercentilePrice) >>"$(getTmp)/nowline.gp"
}

makeGraph() {
  pushd $(getTmp)
  gnuplot plot && google-chrome tibber.png &
  popd
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
  if [[ -z "$(getPercentilePrice)" ]]; then
    error "percentile price empty"
    printUsageAndExit
    exit 1
  fi
  if [[ -z "$(getPercentile)" ]]; then
    error "percentile empty"
    printUsageAndExit
    exit 1
  fi
  convertData
  setLines
  cp "${SCRIPT_DIR}/plot" $(getTmp)
  makeGraph
}

main "$@"