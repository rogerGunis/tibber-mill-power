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
    --type=*)
      setType "${i/*=/}"
      shift
      ;;
    --username=*|--user=*)
      setUser "${i/*=/}"
      shift
      ;;
    --password=*)
      setPassword "${i/*=/}"
      shift
      ;;
    --host=*)
      setHost "${i/*=/}"
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

setType() {
  TYPE="${1}"
}

getType() {
  echo "${TYPE}"
}

setHost() {
  HOST="${1}"
}

getHost() {
  echo "${HOST:-all}"
}

setTmp() {
  TMP="${1}"
}

getTmp() {
  echo "${TMP:-}"
}

setUser() {
  USER="${1}"
}

getUser() {
  echo "${USER:-}"
}

setHost() {
  HOST="${1}"
}

getHost() {
  echo "${HOST:-}"
}

setPassword() {
  PASSWORD="${1}"
}

getPassword() {
  echo "${PASSWORD:-}"
}

printUsageAndExit() {
  {
    IFS="" read -r -d '' usageText <<EOT
usage: ${SCRIPT_NAME} --tmp=.... temporary directory saving files
                      --host=<ip>
                      --user=<user>
                      --password=<password>
                      --type=<ftp|http>
  example:
     ./${SCRIPT_NAME} --tmp=/tmp/exchange --host=fritz.box --user=upload --password=noSecret --type=ftp
EOT
  } || true
  info "\n${usageText}"
  exit 1
}

ftp(){
  STATUS=$(ping -q -c1 -w1 $(getHost)  2>&1 >/dev/null && ncftpput -u "$(getUser)" -p "$(getPassword)" -C "$(getHost)" $(getTmp)/tibber.png tibber.png && echo "ok" || echo "failed")
  echo "host $(getHost) response: ${STATUS}"
}

http(){
  # STATUS=$(ping -q -c1 -w1 $(getHost)  2>&1 >/dev/null && ncftpput -u "$(getUser)" -p "$(getPassword)" -C "$(getHost)" $(getTmp)/tibber.png tibber.png && echo "ok" || echo "failed")
curl -s 'http://'$(getHost)'/app/main.html' \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' \
  -H 'Accept-Language: de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Connection: keep-alive' \
  -H 'Cookie: SESSID=z9riq7ZqHMBGC9tdgU4CrXiHPPLUu6m27ObxLWXtMp2pw; savelge=us; lastaccount='$(getUser)'; hasfirmcheck=1' \
  -H 'If-Modified-Since: Tue, 05 Jun 2018 08:29:42 GMT' \
  -H 'If-None-Match: "3889773341"' \
  -H 'Referer: http://'$(getHost)'/index.html' \
  -H 'Upgrade-Insecure-Requests: 1' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36' \
  --compressed \
  --insecure

curl -s 'http://'$(getHost)'/protocol.csp?function=set' \
  -H 'Accept: */*' \
  -H 'Accept-Language: de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Cache-Control: no-cache' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Cookie: SESSID=z9riq7ZqHMBGC9tdgU4CrXiHPPLUu6m27ObxLWXtMp2pw; savelge=us' \
  -H 'If-Modified-Since: 0' \
  -H 'Origin: http://'$(getHost)'' \
  -H 'Referer: http://'$(getHost)'/index.html' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36' \
  --data-raw 'fname=security&opt=pwdchk&name='$(getUser)'&pwd1='$(getPassword) \
  --compressed \
  --insecure

curl -s 'http://'$(getHost)'/upload.csp?uploadpath=/data/UsbDisk1/Volume1/Share/DCIM&file=file1679164276825&session=DE4ri41qPWOPIzWUxXLL8AJRbOA2MzthdoynrADfrrVaQ' \
  -H 'Accept: */*' \
  -H 'Accept-Language: de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Cache-Control: no-cache' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryAFIT8O7FEUGF2liP' \
  -H 'Cookie: lastaccount='$(getUser)'; SESSID=z9riq7ZqHMBGC9tdgU4CrXiHPPLUu6m27ObxLWXtMp2pw; savelge=us; hasfirmcheck=0; padlistrstop=0px' \
  -H 'If-Modified-Since: 0' \
  -H 'Origin: http://'$(getHost)'' \
  -H 'Referer: http://'$(getHost)'/app/explorer/explorer.html' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36' \
  --data-raw $'------WebKitFormBoundaryAFIT8O7FEUGF2liP\r\nContent-Disposition: form-data; name="@'$(getTmp)/tibber.png'"; filename="tibber.png"\r\nContent-Type: image/png\r\n\r\n\r\n------WebKitFormBoundaryAFIT8O7FEUGF2liP--\r\n' \
  -d@tibber.png \
  --compressed \
  --insecure
  echo "host $(getHost) response: unknown"
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

  $(getType)
}

main "$@"
