#!/bin/sh
# Generates the nginx config from the add-on options and runs nginx in the
# foreground. The token only lives in /data/options.json (managed by the
# Supervisor) and in the generated config (mode 600, outside /data).
set -eu

OPTIONS=/data/options.json
CONF=/etc/nginx/git-proxy.conf

TOKEN=$(jq -r '.github_token // ""' "$OPTIONS")
if [ -z "$TOKEN" ]; then
  echo "[git-proxy] ERROR: github_token is not set" >&2
  exit 1
fi
AUTH=$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')

# One case-insensitive regex per allowed repo, e.g.  "~*^owner/repo$" 1;
REPO_MAP=$(jq -r '.allowed_repos[] | gsub("\\."; "\\.") | "    \"~*^" + . + "$\" 1;"' "$OPTIONS")
if [ -z "$REPO_MAP" ]; then
  echo "[git-proxy] ERROR: allowed_repos is empty" >&2
  exit 1
fi

# github.com is resolved at request time, so the add-on starts even if DNS
# is not ready yet at boot.
RESOLVER=$(awk '/^nameserver/ { ns = $2; if (ns ~ /:/) ns = "[" ns "]"; printf "%s ", ns }' /etc/resolv.conf)
[ -n "$RESOLVER" ] || RESOLVER=127.0.0.11

umask 077
cat > "$CONF" <<NGINX
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;

events { worker_connections 64; }

http {
  # Query strings and headers are not logged, so nothing sensitive is printed.
  log_format git '\$remote_addr "\$request_method \$uri" \$status \$body_bytes_sent \${request_time}s';
  access_log /dev/stdout git;

  resolver ${RESOLVER} valid=300s ipv6=off;
  resolver_timeout 10s;

  client_max_body_size 0;
  proxy_buffering off;
  proxy_request_buffering off;
  proxy_read_timeout 300s;
  proxy_send_timeout 300s;

  map "\$owner/\$name" \$repo_allowed {
    default 0;
${REPO_MAP}
  }

  # Smart-HTTP fetch only. Push (git-receive-pack) never matches.
  map "\$request_method:\$op:\$arg_service" \$op_allowed {
    default 0;
    "GET:info/refs:git-upload-pack" 1;
    "~^POST:git-upload-pack:" 1;
  }

  server {
    listen 8080;
    server_tokens off;

    location = /healthz { access_log off; return 200 "ok\n"; }

    location ~ ^/(?<owner>[A-Za-z0-9_.-]+)/(?<name>[A-Za-z0-9_.-]+?)(?:\.git)?/(?<op>info/refs|git-upload-pack)\$ {
      if (\$repo_allowed = 0) { return 403 "repository not allowed\n"; }
      if (\$op_allowed = 0)   { return 403 "operation not allowed\n"; }

      set \$upstream github.com;
      proxy_pass https://\$upstream;
      proxy_http_version 1.1;
      proxy_set_header Host github.com;
      proxy_set_header Authorization "Basic ${AUTH}";
      proxy_set_header Cookie "";
      proxy_set_header X-Forwarded-For "";
      proxy_set_header X-Real-IP "";
      proxy_redirect https://github.com/ /;

      proxy_ssl_server_name on;
      proxy_ssl_name github.com;
      proxy_ssl_verify on;
      proxy_ssl_verify_depth 4;
      proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
    }

    location / { return 403 "forbidden\n"; }
  }
}
NGINX

echo "[git-proxy] serving: $(jq -r '.allowed_repos | join(", ")' "$OPTIONS")"
exec nginx -c "$CONF" -g 'daemon off;'
