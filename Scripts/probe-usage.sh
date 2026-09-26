#!/bin/bash
# Fase 0: mira quina forma té la resposta de /api/oauth/usage.
# Treu el token del Keychain, fa la crida i imprimeix NOMÉS l'estructura:
# claus, tipus i valors numèrics o de data. Cap token, cap cadena llarga.
set -uo pipefail

RAW=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
if [ -z "$RAW" ]; then
  echo "ERROR: no he trobat 'Claude Code-credentials' al Keychain."
  echo "Si Claude Code hi va amb ANTHROPIC_API_KEY o un token de setup-token, digue-m'ho."
  exit 1
fi

TOKEN=$(printf '%s' "$RAW" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("", end=""); sys.exit()
def find(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k.lower() in ("accesstoken","access_token") and isinstance(v,str):
                return v
            r=find(v)
            if r: return r
    elif isinstance(o,list):
        for v in o:
            r=find(v)
            if r: return r
    return None
print(find(d) or "", end="")
')

if [ -z "$TOKEN" ]; then
  echo "ERROR: la credencial existeix però no en sé treure cap accessToken."
  exit 1
fi

echo "Token llegit: ${#TOKEN} caràcters. No s'imprimeix."
echo

for EP in /api/oauth/usage /api/oauth/profile; do
  echo "=== GET https://api.anthropic.com$EP"
  BODY=$(mktemp)
  CODE=$(curl -s -o "$BODY" -w '%{http_code}' --max-time 20 \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    "https://api.anthropic.com$EP")
  echo "HTTP $CODE"
  python3 - "$BODY" <<'PY'
import json, sys, re
path = sys.argv[1]
raw = open(path, encoding="utf-8", errors="replace").read()
try:
    data = json.loads(raw)
except Exception:
    print("  (resposta no JSON, primers 200 car.)")
    print("  " + raw[:200].replace("\n", " "))
    sys.exit()

SAFE = re.compile(r"^[0-9T:\-\.\+Zz ]+$")

def show(node, indent="  "):
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, (dict, list)):
                print(f"{indent}{k}:")
                show(v, indent + "  ")
            elif isinstance(v, (int, float, bool)) or v is None:
                print(f"{indent}{k} = {v!r}")
            elif isinstance(v, str):
                # imprimim la cadena només si sembla una data o és molt curta
                if SAFE.match(v) or len(v) <= 24:
                    print(f"{indent}{k} = {v!r}")
                else:
                    print(f"{indent}{k} = <str, {len(v)} car.>")
    elif isinstance(node, list):
        print(f"{indent}<llista de {len(node)}>")
        if node:
            show(node[0], indent + "  ")

show(data)
PY
  rm -f "$BODY"
  echo
done
