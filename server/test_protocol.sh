#!/usr/bin/env bash
#
# End-to-end protocol checks against a running server.
#
#   ./test_protocol.sh https://box.tail590aa.ts.net:8443 "$TOKEN"
#
set -uo pipefail

BASE="${1:?usage: test_protocol.sh <base-url> <token>}"
TOKEN="${2:?usage: test_protocol.sh <base-url> <token>}"

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ok    ${name}"
    pass=$((pass + 1))
  else
    echo "  FAIL  ${name}: expected ${expected}, got ${actual}"
    fail=$((fail + 1))
  fi
}

post() {
  curl -s -X POST "${BASE}/financekit-sync" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$1"
}

# A transaction id unique to this run, so repeated runs stay independent.
ID="test-$(date +%s)-$$"
ACCT="acct-${ID}"

packet() {
  cat <<JSON
{
  "schema_version": 1,
  "accounts": [
    {"id": "${ACCT}", "name": "Test Card", "institution": "Test Bank",
     "balance": ${2}, "currency": "USD"}
  ],
  "transactions": [
    {"id": "${ID}", "account_id": "${ACCT}", "date": "2026-08-01T12:00:00.000Z",
     "amount": ${1}, "currency": "USD", "payee": "TEST MERCHANT",
     "status": "posted", "notes": "booked", "category": "5814",
     "metadata": {"source": "test", "wallet": {"transaction_id": "${ID}"}}}
  ]
}
JSON
}

echo "Testing ${BASE}"

echo
echo "auth"
code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/health")
check "/health needs no token" "200" "$code"

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE}/financekit-sync" \
  -H 'Content-Type: application/json' -d '{"schema_version":1}')
check "POST without token is rejected" "401" "$code"

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE}/financekit-sync" \
  -H 'Authorization: Bearer wrong-token' \
  -H 'Content-Type: application/json' -d '{"schema_version":1}')
check "POST with wrong token is rejected" "401" "$code"

code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE}/accounts")
check "GET /accounts without token is rejected" "401" "$code"

echo
echo "ingest"
r=$(post "$(packet -42.10 1000.00)")
check "first send inserts"  "1" "$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["transactions_inserted"])')"
check "first send updates 0" "0" "$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["transactions_updated"])')"

r=$(post "$(packet -42.10 1000.00)")
check "identical replay inserts 0" "0" "$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["transactions_inserted"])')"
check "identical replay updates 1" "1" "$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["transactions_updated"])')"

r=$(post "$(packet -99.99 1234.56)")
check "changed amount updates" "1" "$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["transactions_updated"])')"

amount=$(curl -s "${BASE}/transactions?limit=1000" -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import json,sys;print(next(t['amount'] for t in json.load(sys.stdin)['transactions'] if t['id']=='${ID}'))")
check "stored amount reflects the update" "-99.99" "$amount"

balance=$(curl -s "${BASE}/accounts" -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c "import json,sys;print(next(a['balance'] for a in json.load(sys.stdin)['accounts'] if a['id']=='${ACCT}'))")
check "account balance reflects the update" "1234.56" "$balance"

echo
echo "schema"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${BASE}/financekit-sync" \
  -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d '{"schema_version": 99, "accounts": [], "transactions": []}')
check "unknown schema_version is rejected" "422" "$code"

r=$(post_empty=$(curl -s -X POST "${BASE}/financekit-sync" \
  -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' \
  -d '{"schema_version":1,"accounts":[],"transactions":[]}'); echo "$post_empty")
check "accounts-only packet is accepted" "0" "$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["transactions_received"])')"

echo
echo "${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
