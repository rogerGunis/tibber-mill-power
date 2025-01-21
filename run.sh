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
MILL=()
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
  test -n "${LOG_DEST}" && cp "${LOG_FILE}" "${LOG_DEST}"
  test -f "${TMP_DIR}/tibber.png" && cp "${TMP_DIR}/tibber.png" "${LOG_DEST}"
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
      shift
      ;;
    --dry | -d)
      setDryRun
      shift
      ;;
    --percentile=*| -p=*)
      setPercentile "${i#*=}"
      shift
      ;;
    --mill=*| -m=*)
      setMill "${i#*=}"
      shift
      ;;
    *)
      error "Unknown option: ${i}"
      shift
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

setPercentile() {
   PERCENTILE=$1
}

getPercentile() {
   echo "${PERCENTILE:-70}"
}

setMill() {
   MILL+=(${1//,/ })
}

getMill() {
   echo "${MILL[*]}"
}

main() {
  # info "SCRIPT_DIR is ${SCRIPT_DIR}"
  # info "SCRIPT_PATH is ${SCRIPT_PATH}"
  # info "SCRIPT_NAME is ${SCRIPT_NAME}"
  # info "BASH_SOURCE is ${BASH_SOURCE[@]}"
  if [[ -f .env ]]; then
    source .env
  fi

  parseArguments "$@"

  if [[ -z "${TMP_DIR:-}" ]];then
    echo "tmp dir not set"
    exit 1;
  else
    mkdir -p "${TMP_DIR}"
  fi

  if [[ -d ".git" ]];then
    git stash
    git pull
    git stash pop || true
  fi

  mkdir -p "${TMP_DIR}"
  info "step 10"
  ./10-*/execute.sh --tmp="${TMP_DIR}" --token="${TIBBER_TOKEN:-5K4MVS-OjfWhK_4yrjOlFe1F6kJXPVf7eQYggo8ebAE}"

  info "step 20"
  PERCENTILE_PRICE_TODAY=$(./20-*/execute.sh --tmp="${TMP_DIR}" --day=today --percentile="$(getPercentile)")
  PERCENTILE_PRICE_TOMORROW=$(./20-*/execute.sh --tmp="${TMP_DIR}" --day=tomorrow --percentile="$(getPercentile)")

  info "step 25"
  ./25-*/execute.sh --tmp="${TMP_DIR}" --percentile-price-today="${PERCENTILE_PRICE_TODAY}" --percentile-price-tomorrow="${PERCENTILE_PRICE_TOMORROW}"

  info "step 30"
  for millId in $(getMill);do
    info "starting mill $millId"
    isDryRun || ./30-*/execute.sh --tmp="${TMP_DIR}" --host=power${millId} # --token="${MILL_TOKEN:-}"
  done

  info "step 40"
  ./40-*/execute.sh --tmp="${TMP_DIR}" --percentile-price-today="${PERCENTILE_PRICE_TODAY}" --percentile-price-tomorrow="${PERCENTILE_PRICE_TOMORROW}" --percentile="$(getPercentile)"

  info "step 50"
  if [[ -n "${FTP_HOST:-}" ]];then
      ./50-*/execute.sh --tmp="${TMP_DIR}" --username="${FTP_USER}" --password="${FTP_PASS}" --host="${FTP_HOST}" --type=ftp
  fi
  info "step 60"
  if [[ -n "${HTTP_HOST:-}" ]];then
      ./50-*/execute.sh --tmp="${TMP_DIR}" --username="${HTTP_USER}" --password="${HTTP_PASS}" --host="${HTTP_HOST}" --type=http
  fi
}

main "$@"
