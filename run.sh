#!/bin/bash
source .env

TMP_DIR=/tmp/exchange
PERCENTILE=70

mkdir -p "${TMP_DIR}"
./10-*/execute.sh --tmp="${TMP_DIR}" --token="${TIBBER_TOKEN}"

PERCENTILE_PRICE_TODAY=$(./20-*/execute.sh --tmp="${TMP_DIR}" --day=today --percentile="${PERCENTILE}")
PERCENTILE_PRICE_TOMORROW=$(./20-*/execute.sh --tmp="${TMP_DIR}" --day=tomorrow --percentile="${PERCENTILE}")

./25-*/execute.sh --tmp="${TMP_DIR}" --percentile-price-today="${PERCENTILE_PRICE_TODAY}" --percentile-price-tomorrow="${PERCENTILE_PRICE_TOMORROW}"

./30-*/execute.sh --tmp="${TMP_DIR}" --percentile-price="${PERCENTILE_PRICE_TODAY}" --percentile="${PERCENTILE}"

./40-*/execute.sh --tmp="${TMP_DIR}" --username="${FTP_USER}" --password="${FTP_PASS}" --host="${FTP_HOST}"
