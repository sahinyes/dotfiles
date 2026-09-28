# shellcheck shell=bash
# Downloads. One entry point, fetch URL OUT, which tries curl, then python3's
# urllib, then wget, so a machine that has only one of them still works. All
# three honour https_proxy. Only https URLs are requested, and curl and python3
# also refuse redirects to anything but https. wget cannot restrict redirects,
# so on a wget-only machine a redirect may travel over plain http. Integrity
# never rests on the transport: every download is checked against its sha256
# (lib/verify.sh) before use. (wget runs with --no-hsts so it leaves no
# ~/.wget-hsts behind.)

# fetch_tool: name of the downloader fetch will use (or "none").
fetch_tool() {
  if have curl; then
    echo curl
  elif have python3; then
    echo python3
  elif have wget; then
    echo wget
  else
    echo none
  fi
}

# fetch_once URL PART: one download attempt with the first available tool.
fetch_once() {
  case $(fetch_tool) in
    curl)
      curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 1200 -o "$2" "$1"
      ;;
    wget) wget -q --no-hsts --timeout=30 --tries=1 -O "$2" "$1" ;;
    python3)
      python3 - "$1" "$2" <<'PY'
import shutil, sys, urllib.error, urllib.request


class HttpsOnly(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise urllib.error.URLError("refusing redirect to " + newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


url, out = sys.argv[1], sys.argv[2]
opener = urllib.request.build_opener(HttpsOnly)
with opener.open(url, timeout=60) as r, open(out, "wb") as f:
    shutil.copyfileobj(r, f)
PY
      ;;
    *)
      warn "no downloader: install curl, wget or python3"
      return 1
      ;;
  esac
}

# fetch URL OUT: download URL to OUT (atomically, via a .part file). Three
# attempts, because mirrors sometimes drop long transfers.
fetch() {
  local url=$1 out=$2 part="$2.part.$$.$RANDOM" attempt
  case $url in
    https://*) ;;
    *)
      warn "refusing non-https URL: $url"
      return 1
      ;;
  esac
  for attempt in 1 2 3; do
    rm -f "$part"
    if fetch_once "$url" "$part"; then
      mv -f "$part" "$out"
      return 0
    fi
    warn "download attempt $attempt failed: $url"
    sleep "$attempt"
  done
  rm -f "$part"
  return 1
}

# net_probe: true when https://github.com/ answers within a few seconds.
net_probe() {
  local url=https://github.com/
  case $(fetch_tool) in
    curl) curl -fsS -o /dev/null --connect-timeout 5 --max-time 20 "$url" 2>/dev/null ;;
    wget) wget -q --no-hsts --spider --timeout=10 --tries=1 "$url" 2>/dev/null ;;
    python3)
      python3 -c 'import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=15)' \
        "$url" 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}
