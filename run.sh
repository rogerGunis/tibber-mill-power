#!/usr/bin/env bash

LOG_FILE=$(pwd)/tibber.log
exec > >(tee ${LOG_FILE}) 2>&1

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
    --help | -h)
      printUsageAndExit
      ;;
    --dry | -d)
      setDryRun
      ;;
    *)
      error "Unknown option: ${i}"
      printUsageAndExit
      ;;
    esac
  done
}

printUsageAndExit() {
  {
    IFS="" read -r -d '' usageText <<EOT
usage: ${SCRIPT_NAME}

  example:
     ./${SCRIPT_NAME}
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

setDryRun() {
  local TRUE=0
  DRY=$TRUE
}

isDryRun(){
  return ${DRY:-1}
}

main() {
  # info "SCRIPT_DIR is ${SCRIPT_DIR}"
  # info "SCRIPT_PATH is ${SCRIPT_PATH}"
  # info "SCRIPT_NAME is ${SCRIPT_NAME}"
  # info "BASH_SOURCE is ${BASH_SOURCE[@]}"
  parseArguments "$@"

  if [[ -f .env ]]; then
    source .env
  fi

  if [[ -z "${TMP_DIR:-}" ]];then
    echo "tmp dir not set"
    exit 1;
  else
    mkdir -p "${TMP_DIR}"
  fi

  if [[ -d ".git" ]];then
    git stash
    git pull
    git stash pop
  fi

  PERCENTILE=70

  mkdir -p "${TMP_DIR}"
  info "10"
  ./10-*/execute.sh --tmp="${TMP_DIR}" --token="${TIBBER_TOKEN:-5K4MVS-OjfWhK_4yrjOlFe1F6kJXPVf7eQYggo8ebAE}"

  PERCENTILE_PRICE_TODAY=$(./20-*/execute.sh --tmp="${TMP_DIR}" --day=today --percentile="${PERCENTILE}")
  PERCENTILE_PRICE_TOMORROW=$(./20-*/execute.sh --tmp="${TMP_DIR}" --day=tomorrow --percentile="${PERCENTILE}")

  info "25"
  ./25-*/execute.sh --tmp="${TMP_DIR}" --percentile-price-today="${PERCENTILE_PRICE_TODAY}" --percentile-price-tomorrow="${PERCENTILE_PRICE_TOMORROW}"

  info "30"
  isDryRun || ./30-*/execute.sh --tmp="${TMP_DIR}" --host=power1 --token="${MILL_TOKEN:-}"
  isDryRun || ./30-*/execute.sh --tmp="${TMP_DIR}" --host=power2 --token="${MILL_TOKEN:-}"

  info "40"
  ./40-*/execute.sh --tmp="${TMP_DIR}" --percentile-price-today="${PERCENTILE_PRICE_TODAY}" --percentile-price-tomorrow="${PERCENTILE_PRICE_TOMORROW}" --percentile="${PERCENTILE}"

  info "50"
  if [[ -n "${FTP_HOST:-}" ]];then
      ./50-*/execute.sh --tmp="${TMP_DIR}" --username="${FTP_USER}" --password="${FTP_PASS}" --host="${FTP_HOST}" --type=ftp
  fi
  if [[ -n "${HTTP_HOST:-}" ]];then
      ./50-*/execute.sh --tmp="${TMP_DIR}" --username="${HTTP_USER}" --password="${HTTP_PASS}" --host="${HTTP_HOST}" --type=http
  fi
}

main "$@"
