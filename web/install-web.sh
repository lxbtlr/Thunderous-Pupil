#!/bin/bash
# Install the static query + chart page into a web-served directory.
#
#   ./web/install-web.sh /tank/www/alexb/swole/db
#
# Idempotent. Vendors sql.js and Vega so the page never needs a CDN at
# runtime, then copies index.html. Does NOT touch your database or the job
# that copies it -- the page reads whatever is already sitting there.
set -euo pipefail
WEB="${1:?usage: install-web.sh WEBDIR}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$WEB"; cd "$WEB"
say() { printf '  %-26s %s\n' "$1" "$2"; }
FAILED=0

if [[ -s sql-wasm.js && -s sql-wasm.wasm ]]; then say "sql.js" "already present"
elif curl -sfL https://github.com/sql-js/sql.js/releases/latest/download/sqljs-wasm.zip -o sqljs.zip; then
  unzip -oqj sqljs.zip 'sql-wasm.js' 'sql-wasm.wasm' && rm -f sqljs.zip
  say "sql.js" "installed"
else say "sql.js" "DOWNLOAD FAILED"; FAILED=1; fi

# jsDelivr first, npm registry tarball as fallback: campus networks block one
# or the other often enough to be worth handling.
for pkg in vega vega-lite vega-embed; do
  out="$pkg.min.js"
  if [[ -s $out ]]; then say "$out" "already present"; continue; fi
  curl -sfL "https://cdn.jsdelivr.net/npm/$pkg/build/$out" -o "$out" 2>/dev/null || true
  if [[ ! -s $out ]]; then
    tgz=$(curl -sf "https://registry.npmjs.org/$pkg/latest" \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['dist']['tarball'])" 2>/dev/null) || true
    if [[ -n ${tgz:-} ]] && curl -sfL "$tgz" -o "$pkg.tgz"; then
      tar xzf "$pkg.tgz" --wildcards "package/build/$out" 2>/dev/null \
        && mv "package/build/$out" . ; rm -rf "$pkg.tgz" package
    fi
  fi
  if [[ -s $out ]]; then say "$out" "$(stat -c%s "$out") bytes"
  else say "$out" "DOWNLOAD FAILED"; FAILED=1; rm -f "$out"; fi
done

# Regenerate the views from web/views/*.md before copying, so the page always
# ships what the markdown says. Skipped if there is no views dir (older
# layouts) or no python3.
if [[ -d "$HERE/views" ]] && command -v python3 >/dev/null; then
  if "$HERE/../bin/build-views" >/tmp/bv.$$ 2>&1; then
    say "views.json" "$(grep -c '^  \(chart\|table\)' /tmp/bv.$$) views built from markdown"
  else
    say "views.json" "BUILD FAILED -- see below; keeping the previous file"
    sed 's/^/      /' /tmp/bv.$$ | tail -12
    FAILED=1
  fi
  rm -f /tmp/bv.$$
fi

if [[ -s "$HERE/views.json" ]]; then
  cp "$HERE/views.json" .
  say "views.json" "copied ($(stat -c%s views.json) bytes)"
else
  say "views.json" "MISSING -- page will load with no view buttons"
  FAILED=1
fi

cp "$HERE/index.html" .
chmod 644 index.html views.json ./*.js ./*.wasm 2>/dev/null || true
say "index.html" "copied"

echo
DB=""
for n in corpus.sqlite corpus.db publish.sqlite; do [[ -s $n ]] && DB=$n && break; done
if [[ -n $DB ]]; then
  say "database" "$DB ($(du -h "$DB" | cut -f1))"
else
  echo "  No database here yet. Your 30-minute copy job should land one as"
  echo "  corpus.sqlite or corpus.db; the page tries both."
fi
if [[ $FAILED -eq 1 ]]; then
  echo
  echo "  Fetch the missing files on a networked machine and scp them in:"
  echo "    sql-wasm.js sql-wasm.wasm vega.min.js vega-lite.min.js vega-embed.min.js"
fi
echo
echo "  If the page hangs on 'loading database', the server is sending .wasm as"
echo "  application/octet-stream. Add to .htaccess:  AddType application/wasm .wasm"
