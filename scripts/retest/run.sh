#!/usr/bin/env bash
# End-to-end Docker retest for the SSH feature: proves ssh-agent auth, key-file
# fallback, `ssh -G` alias resolution and strict known_hosts verification
# through a real bastion jump to an unpublished target.
#
# Throwaway validation infrastructure, not shipped code: it has no unit
# tests, it IS the test. Fully self-cleaning (see cleanup() below).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BASTION_NAME="ae_retest_bastion"
TARGET_NAME="ae_retest_target"
NETWORK_NAME="ae_retest_net"
IMAGE_NAME="ae_retest_sshd"
BASTION_PORT="12222"

FAILED_STEP=""

# Tears down everything the retest creates, on every exit path (success,
# failure, or interruption). Registered before anything is created.
cleanup() {
  local status=$?
  set +e
  if [ -n "${SSH_AGENT_PID:-}" ]; then
    ssh-agent -k >/dev/null 2>&1 || kill "${SSH_AGENT_PID}" >/dev/null 2>&1
  fi
  docker rm -f "$BASTION_NAME" "$TARGET_NAME" >/dev/null 2>&1
  docker network rm "$NETWORK_NAME" >/dev/null 2>&1
  docker rmi "$IMAGE_NAME" >/dev/null 2>&1
  if [ -n "${WORK:-}" ]; then
    rm -rf "$WORK"
  fi
  if [ -n "$FAILED_STEP" ]; then
    echo "FAILED at step: $FAILED_STEP" >&2
  elif [ "$status" -ne 0 ]; then
    echo "FAILED (exit $status)" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

fail() {
  FAILED_STEP="$1"
  echo "$1" >&2
  exit 1
}

# 1. Scratch workspace + scratch HOME (never touches the real ~/.ssh).
WORK=$(mktemp -d)
export HOME_SCRATCH="$WORK/home"
mkdir -p "$HOME_SCRATCH/.ssh"
chmod 700 "$HOME_SCRATCH/.ssh"

# 2. Throwaway key + ssh config with the two aliases ssherlock resolves
# via `ssh -G`.
ssh-keygen -t ed25519 -N "" -f "$WORK/key" -q

cat >"$HOME_SCRATCH/.ssh/config" <<EOF
Host retest-bastion
  HostName 127.0.0.1
  Port ${BASTION_PORT}
  User root
  IdentityFile ${WORK}/key
Host retest-target
  HostName ${TARGET_NAME}
  Port 22
  User root
  IdentityFile ${WORK}/key
EOF
chmod 600 "$HOME_SCRATCH/.ssh/config"

# OpenSSH resolves the default "~/.ssh/config" via the passwd-entry home
# directory (getpwuid), NOT the $HOME environment variable, so simply
# exporting HOME does not redirect `ssh -G` (which ssherlock shells out
# to, and which the (c) proof below also calls directly) to our scratch
# config. Shim a `ssh` on PATH that forces `-F` to the scratch config file;
# every other flag/option passed through untouched.
REAL_SSH="$(command -v ssh)"
mkdir -p "$WORK/bin"
cat >"$WORK/bin/ssh" <<SHIM
#!/bin/sh
exec "${REAL_SSH}" -F "${HOME_SCRATCH}/.ssh/config" "\$@"
SHIM
chmod +x "$WORK/bin/ssh"
export PATH="$WORK/bin:$PATH"

# 3. Build the sshd image (no build context needed; authorized_keys is
# injected after the containers start).
docker build -t "$IMAGE_NAME" -f scripts/retest/Dockerfile.sshd scripts/retest >"$WORK/docker_build.log" 2>&1 \
  || fail "docker build failed (see $WORK/docker_build.log)"

# 4. Private network: the target is only reachable from inside it.
docker network create "$NETWORK_NAME" >/dev/null

# 5. Bastion published on host loopback; target NOT published.
docker run -d --name "$BASTION_NAME" --network "$NETWORK_NAME" \
  -p "127.0.0.1:${BASTION_PORT}:22" "$IMAGE_NAME" >/dev/null
docker run -d --name "$TARGET_NAME" --network "$NETWORK_NAME" "$IMAGE_NAME" >/dev/null

# 6. Authorise the throwaway key on both containers.
for c in "$BASTION_NAME" "$TARGET_NAME"; do
  docker exec "$c" sh -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'
  docker cp "$WORK/key.pub" "$c:/root/.ssh/authorized_keys"
  # docker cp preserves the host UID on the copied file; sshd's strict-modes
  # check silently rejects authorized_keys not owned by root, so re-own it.
  docker exec "$c" chown root:root /root/.ssh/authorized_keys
  docker exec "$c" chmod 600 /root/.ssh/authorized_keys
done

# 7. Wait for the bastion's sshd to answer on the published port.
BASTION_READY=0
for _ in $(seq 1 30); do
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -i "$WORK/key" -p "$BASTION_PORT" root@127.0.0.1 true >/dev/null 2>&1; then
    BASTION_READY=1
    break
  fi
  sleep 1
done
[ "$BASTION_READY" -eq 1 ] || fail "bastion sshd never became reachable on 127.0.0.1:${BASTION_PORT}"

# 8. Build the ssherlock binary once; every proof below reuses it.
if [ ! -d licenses ]; then
  bash scripts/harvest-licenses.sh
fi
crystal build src/ssherlock.cr -o "$WORK/ssherlock" >"$WORK/crystal_build.log" 2>&1 \
  || fail "crystal build failed (see $WORK/crystal_build.log)"

# Runs the binary against <config>, then checks <output_dir>/<label>.json for
# a null top-level error (i.e. the collection itself succeeded — individual
# check command failures don't count, only auth/connection/host-key errors do).
# Envelope#error is a plain `String?` getter (no `emit_null` annotation), so
# Crystal's JSON::Serializable omits the key entirely when nil instead of
# emitting `"error": null` — success is the ABSENCE of an "error" key.
collected_ok() {
  local cfg="$1" out_dir="$2" label="$3"
  HOME="$HOME_SCRATCH" "$WORK/ssherlock" run "$cfg" >"$WORK/last_run.log" 2>&1 || true
  [ -f "$out_dir/$label.json" ] || return 1
  ! grep -q '"error":' "$out_dir/$label.json"
}

write_via_bastion_config() {
  local out_dir="$1"
  cat >"$WORK/via-bastion.yml" <<EOF
output_dir: ${out_dir}
concurrency: 1
servers:
  - host: retest-target
    label: t1
    inherit: linux
    ssh:
      bastion: retest-bastion
      config: true
EOF
}

cat >"$WORK/direct.yml" <<EOF
output_dir: ${WORK}/out_d
concurrency: 1
servers:
  - host: retest-bastion
    label: b1
    inherit: linux
    ssh:
      bastion: none
      verify_host_key: known_hosts
      config: true
EOF

# --- (a) agent auth through the bastion to the unpublished target ---------
# The agent holds the key in memory; the key file is then made unreadable so
# only login_with_agent can succeed.
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$WORK/key" >/dev/null 2>&1
chmod 000 "$WORK/key"

write_via_bastion_config "$WORK/out_a"
collected_ok "$WORK/via-bastion.yml" "$WORK/out_a" t1 \
  || fail "(a) agent auth through bastion did not produce a clean collection"
echo "a: OK"

# --- (b) key-file fallback, no agent ---------------------------------------
ssh-agent -k >/dev/null 2>&1 || true
unset SSH_AUTH_SOCK SSH_AGENT_PID
chmod 600 "$WORK/key"

write_via_bastion_config "$WORK/out_b"
collected_ok "$WORK/via-bastion.yml" "$WORK/out_b" t1 \
  || fail "(b) key-file fallback through bastion did not produce a clean collection"
echo "b: OK"

# --- (c) ssh -G alias resolution --------------------------------------------
# Confirms the alias resolution that made (a)/(b) work: retest-target
# resolves to the unpublished container name inside the docker network.
G_OUTPUT="$(HOME="$HOME_SCRATCH" ssh -G retest-target)"
echo "$G_OUTPUT" | grep -qx "hostname ${TARGET_NAME}" \
  || fail "(c) ssh -G retest-target did not resolve hostname ${TARGET_NAME}"
echo "c: OK"

# --- (d) strict known_hosts, direct connection to the published bastion ----
# Seed known_hosts under the ALIAS name (the identity ssherlock verifies
# against), not the [ip]:port ssh-keyscan reports. Seed ALL host-key types
# ssh-keyscan returns (rsa, ecdsa, ed25519), not just the first: libssh2
# negotiates its own preferred host-key algorithm, and the seeded entry must
# cover whichever type the session actually ends up using, or the check
# reports NOTFOUND for a key that is genuinely the server's.
RAW_HOSTKEYS="$(ssh-keyscan -p "$BASTION_PORT" 127.0.0.1 2>/dev/null | grep -v '^#')"
[ -n "$RAW_HOSTKEYS" ] || fail "(d) ssh-keyscan returned no host key for the bastion"
echo "$RAW_HOSTKEYS" | sed "s#^\[127\.0\.0\.1\]:${BASTION_PORT}#retest-bastion#" >"$HOME_SCRATCH/.ssh/known_hosts"
chmod 600 "$HOME_SCRATCH/.ssh/known_hosts"

collected_ok "$WORK/direct.yml" "$WORK/out_d" b1 \
  || fail "(d) direct connection with seeded known_hosts (MATCH) did not produce a clean collection"

# Now blank known_hosts: the run must not crash, and must record a non-null,
# host-key-related error (strict refuse — MATCH-only policy).
: >"$HOME_SCRATCH/.ssh/known_hosts"
HOME="$HOME_SCRATCH" "$WORK/ssherlock" run "$WORK/direct.yml" >"$WORK/last_run.log" 2>&1 || true
[ -f "$WORK/out_d/b1.json" ] || fail "(d) missing b1.json after known_hosts was blanked"
grep -q '"error":' "$WORK/out_d/b1.json" \
  || fail "(d) collection unexpectedly succeeded with an empty known_hosts file"
grep -qi "host key" "$WORK/out_d/b1.json" \
  || fail "(d) b1.json error does not mention the host key: $(cat "$WORK/out_d/b1.json")"
echo "d: OK"

echo "RETEST OK"
