# Production Private APT Service — Interface Contract

> **Spec reference:** §14.10 (production private APT service — not implemented
> this round) and §14.7 (Origin/Label/Allowed-Origins lockstep).
>
> **Status:** This document is an **interface contract / hand-off only**
> (spec §14.10 boundary). The Byclaw POC does **not** implement the production
> private-APT service. The POC ships a local filesystem aptly repository served
> over plain HTTP on `127.0.0.1:8099` (see
> [`poc/apt-repository/aptly.conf`](../../poc/apt-repository/aptly.conf) and
> [`poc/scripts/serve-repo.sh`](../../poc/scripts/serve-repo.sh)). Everything
> below describes what the production service *must* provide; it is not built
> here.

---

## 1. Transport

| | POC | Production (contract) |
|---|---|---|
| Scheme | `http://` | **`https://`** |
| Bind | `127.0.0.1:8099` (`python3 -m http.server`) | publisher hostname / CDN edge, TLS-terminated |
| Auth | none (single trusted publisher, localhost) | mTLS or signed-asset origin pinning; never `Trusted: yes` |
| Endpoint | `FileSystemPublishEndpoint` (`local`) | remote aptly / repo mirror / CDN front |

The POC serves `update-policy.json` (the policy the Electron main process
fetches) and the signed APT indices from the same `127.0.0.1:8099` root. In
production the policy endpoint and the APT repo must both be HTTPS (spec §8.5:
"POC 用本地 HTTP；生产必须 HTTPS"). The Electron process still only *queries*
versions and displays state — it never downloads or installs a DEB; download
and install remain the job of `unattended-upgrades` over APT.

---

## 2. GPG signing key management + rotation

### 2.1 POC (current)
- A throwaway, **passphrase-less** POC key generated into a fixed `GNUPGHOME`
  (`poc/apt-repository/gpg-home`), with the public key exported to
  `poc/apt-repository/byclaw-poc-public.gpg`.
- The root install chain
  ([`poc/scripts/install-client-config.sh`](../../poc/scripts/install-client-config.sh))
  copies that public key to `/usr/share/keyrings/byclaw-poc.gpg` (`0644`).
- **No rotation, no revocation, no expiry management.** The key material under
  `gpg-home/` is never committed; if it ever is, treat it as compromised.

### 2.2 Production (contract)
- The signing key is a **managed secret** — generated and stored in an HSM or
  a managed secret store (never on the aptly host's local disk in plaintext),
  with a passphrase, a defined expiry, and an audit trail.
- **Key rotation procedure:**
  1. Generate a new signing sub-key (or a new primary key) ahead of the old
     key's expiry.
  2. Publish the new public key alongside the old one (clients accept both
     during a grace window). The keyring file at
     `/usr/share/keyrings/byclaw-poc.gpg` is updated via the same managed-config
     channel used for the sources/apt.conf (OEM image or config management).
  3. Re-sign the repository's `InRelease` / `Release.gpg` with the new key.
  4. After the grace window, **revoke** the old key and remove it from the
     distributed keyring.
- **Compromise / revocation:** publish a revocation certificate through the
  signed distribution channel; clients must refuse upgrades signed by a revoked
  key. Define an out-of-band key-distribution bootstrap (the POC's local
  keyring copy is *not* an acceptable production bootstrap).

---

## 3. Origin / Label / Allowed-Origins lockstep

This is the single most important invariant for `unattended-upgrades` to only
touch Byclaw. The publish metadata and the client apt.conf **must** agree
exactly; a mismatch means the upgrade is silently never applied.

| Field | Value (confirmed in POC config) |
|---|---|
| `Origin` | `Lenovo` (aptly publish `-origin=Lenovo`) |
| `Label` | `Byclaw` (aptly publish `-label=Byclaw`) |
| `Suite` / distribution | `noble` (aptly publish `-distribution=noble`) |
| `Component` | `main` |
| `Allowed-Origins` | `{"Lenovo:noble"}` |

The POC apt.conf value is confirmed verbatim in
[`poc/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades`](../../poc/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades):

```
Unattended-Upgrade::Allowed-Origins { "Lenovo:noble"; };
Unattended-Upgrade::Package-Whitelist { "^byclaw$"; };
Unattended-Upgrade::Package-Blacklist { "unrelated-poc"; "random-test-poc"; };
```

**Production contract:** the production repo must publish with the identical
`Origin: Lenovo`, `Label: Byclaw`, `Suite: noble`, and the production apt.conf
must carry the identical `Allowed-Origins {"Lenovo:noble";}`. A publish
pipeline that emits a different `Origin`/`Label`/`Suite` is a **release
blocker** — per spec §14.7 a mismatch must error, not silently no-op.

The client APT source pins the keyring (not trust) — see
[`poc/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources`](../../poc/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources):

```
Types: deb
URIs: http://127.0.0.1:8099/        # production: https://<publisher>/
Suites: noble
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/byclaw-poc.gpg
```

Note: `Signed-By` (verify signatures) is used; **`Trusted: yes` is forbidden**
(spec §6.5, §16).

---

## 4. Packages index fields

aptly generates the standard APT `Packages` index from each `.deb`'s control
metadata. The contract requires these fields be present and consistent with the
deb on disk:

| Field | Source | Notes |
|---|---|---|
| `Package` | `DEBIAN/control` | `byclaw` |
| `Version` | `DEBIAN/control` `Version` | must equal the build-time single version source (see §12.3 — one of the six consistent places) |
| `Architecture` | `amd64` | |
| `Filename` | aptly | path to the `.deb` in `pool/` |
| `SHA256` | aptly (from the deb) | per-file integrity |
| `Size` | aptly (from the deb) | per-file integrity |

The POC verifies version consistency across six places via
[`poc/scripts/verify-versions.sh`](../../poc/scripts/verify-versions.sh),
including the published `Packages` index `Version` and the HTTP-served
`update-policy.json` `latestVersion`. Production must run the same post-publish
consistency check before declaring a release.

---

## 5. Hash + signature verification

APT verifies the repository in two layers:

1. **Repository metadata** — `InRelease` (inline-signed) and `Release.gpg`
   (detached). Both are GPG-signed with the key pinned by `Signed-By`. A client
   `apt-get update` refuses the indices if the signature is missing, broken, or
   not made by the pinned key.
2. **Per-package integrity** — each entry in `Packages` carries `SHA256` and
   `Size`; APT verifies the downloaded `.deb` against these before installing.

**Tamper rejection (Case 09):** if an attacker modifies `InRelease`, the
`Release`/`Packages` index, or a `.deb` in the pool, APT must refuse the
upgrade (signature or hash mismatch). This is validation Case 09 — **NOT-TESTED**
in the POC pending the root tamper run (queued in
[`poc/ROOT_OPS_RUNBOOK.md`](../../poc/ROOT_OPS_RUNBOOK.md)).

Production contract: the service must guarantee that *no* unsigned or
hash-mismatched package can ever be served as a valid upgrade; any tamper must
be detected and rejected client-side purely from APT's own verification, with
no reliance on the policy endpoint.

---

## 6. POC-vs-production differences

| Dimension | POC (this repo) | Production (contract) |
|---|---|---|
| aptly storage | local filesystem (`FileSystemPublishEndpoints: local`) | remote aptly host / repo mirror / CDN |
| Transport | plain HTTP on `127.0.0.1:8099` | **HTTPS** (TLS-terminated, cert managed) |
| Reach | localhost only (single VM) | publisher hostname, geo-replicated mirror / CDN |
| Signing key | throwaway, passphrase-less, in `poc/apt-repository/gpg-home` | managed secret (HSM / secret store), passphrase, expiry, audit |
| Key distribution | manual local file → `/usr/share/keyrings/byclaw-poc.gpg` | signed config-management channel; key rotation + revocation |
| Key rotation | none | defined grace-window rotation + revocation procedure (§2.2) |
| Repo availability | `serve-repo.sh start` (best-effort, PID + log) | monitoring, SLO, alerting on index freshness / signature validity |
| Timer cadence | 2 min (POC iteration speed) | daily / policy-driven (spec §21) |
| `update-policy.json` | HTTP, served from repo root | HTTPS, same or separate policy endpoint; Electron still only *queries* |
| Whitelist strictness | `Package-Whitelist` is not strict → paired with `Package-Blacklist` (known POC limitation, spec §21) | same pattern carried forward; consider strict allowlist tooling |

---

## 7. Production deployment steps (high-level)

1. **Provision the signing key** in an HSM / managed secret store; generate the
   keypair with a passphrase and defined expiry; capture the public key for
   client distribution.
2. **Stand up the aptly publisher** on a dedicated host (or a managed repo
   service). Configure a fixed `rootDir` and `GNUPGHOME` (the POC's absolute
   fixed paths, spec §14.2, are the model — never `${HOME}`-dependent).
3. **Publish over HTTPS** with `aptly publish repo ... -origin=Lenovo -label=Byclaw -distribution=noble`
   behind a TLS-terminating edge / CDN. Confirm the `Release` file's
   `Origin`/`Label`/`Suite` match the client `Allowed-Origins`.
4. **Distribute client config** (`sources` + `keyring` + `60byclaw-poc-upgrades`
   + systemd timer) via the OEM image or a config-management channel — never
   `Trusted: yes`, never `NOPASSWD`.
5. **Run the post-publish consistency check** (`verify-versions.sh`) over the
   six version places, including the served `Packages` index and
   `update-policy.json`, before declaring the release.
6. **Operate:** monitor repo reachability, TLS cert expiry, signature validity,
   index freshness, and per-package availability; run the key-rotation procedure
   on schedule.

---

## 8. Boundary (explicit)

This POC implements **none** of the production service above. It implements
only the local-filesystem, plain-HTTP, localhost, throwaway-key pattern needed
to *validate the update pattern* end-to-end on one machine. This document is
the interface contract that a production deployment must satisfy (spec §14.10).
The production HTTPS endpoint, key rotation, CDN/mirror, and monitoring are
out of scope for this branch and are tracked as residual risk in spec §21.
