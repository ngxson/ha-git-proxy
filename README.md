# Git Proxy (Home Assistant add-on)

Lets the Home Assistant Supervisor pull **private GitHub add-on repositories**
without putting a token in the repository URL.

Why: the Supervisor has no credential store for add-on repositories. Putting a
token in the URL (`https://<token>@github.com/...`) means:

- the repository slug (and every add-on slug from it) is a hash of the URL, so
  rotating the token forces a reinstall of all its add-ons;
- recent git/libcurl (git 2.54 + libcurl 8.23) mistake a username-only URL for
  a redirect and drop the token (`could not read Username ... No such device or address`).

With this add-on the token lives in the add-on options, and the repository URL
stays the same forever.

## How it works

nginx on port 8080, reachable **only on the internal hassio network** (no host
port). It forwards git smart-HTTP fetch requests to `https://github.com` and
adds `Authorization: Basic x-access-token:<token>`.

- Only `GET <repo>/info/refs?service=git-upload-pack` and
  `POST <repo>/git-upload-pack` are forwarded. Push (`git-receive-pack`) and
  everything else get `403`.
- Only repositories listed in `allowed_repos` are forwarded (case-insensitive).
- The access log contains method, path and status only — no query strings or headers.

## Setup

1. Add this repository to Home Assistant:
   `https://github.com/ngxson/ha-git-proxy`
2. Install **Git Proxy**, set `github_token` (fine-grained PAT, read-only
   *Contents* on the allowed repos) and `allowed_repos`, start it.
3. Add your private repository through the proxy, using the add-on's hostname
   (shown on the add-on info page, `<repo-hash>-git-proxy`):

   ```
   http://<repo-hash>-git-proxy:8080/<owner>/<repo>
   ```

To rotate the token: change `github_token`, restart the add-on. Nothing else changes.

## Notes

- If the proxy is not running when the Supervisor refreshes the store (e.g. the
  first seconds after boot), that refresh fails; the next one works. Installed
  add-ons keep running either way.
- `startup: system` makes it start before regular add-ons.
