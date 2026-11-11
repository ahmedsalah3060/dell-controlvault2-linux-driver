#!/usr/bin/env python3
"""
patch_driver.py - Broadcom ControlVault 2 (BCM5880 / USB 0a5c:5834) Driver Patcher

Transforms Dell / Canonical's proprietary ControlVault 3 fingerprint driver
(libfprint-2-tod-1-broadcom.so) to drive older ControlVault 2 sensors.

It applies 7 byte-level reverse-engineered patches:
  1. id_table: Match USB PID 0x5834 (was 0x5842)
  2. USB enumerator: Accept PID 0x5834 (change `je` to `jmp`)
  3. dev_probe: Chip type 0x1c (no flash) handled as success
  4. enroll state machine: Route CV2 status 0x59 ("data ready") to commit
  5. verify completion: Drop `edx!=0` short-circuit so non-zero verify is reported
  6. commit args: Route cv_fingerprint_commit_enrollment with Dell CV2 BroadcomWBF identity
  7. identity storage: Store identity structure in freed debug string

Usage:
    python3 patch_driver.py <input.so> <output.so>   # Apply patches
    python3 patch_driver.py --check <driver.so>      # Verify patch status
"""
import hashlib
import sys

PATCHES = [
    ("1. id_table: match PID 0x5834",
     bytes.fromhex("42580000 5c0a0000".replace(" ", "")),
     bytes.fromhex("34580000 5c0a0000".replace(" ", ""))),

    ("2. USB enumerator: accept PID 0x5834",
     bytes.fromhex("66f7c1fdff 740c".replace(" ", "")),
     bytes.fromhex("66f7c1fdff eb0c".replace(" ", ""))),

    ("3. dev_probe: chip type 0x1c treated as success",
     bytes.fromhex("83f81c 741f".replace(" ", "")),
     bytes.fromhex("83f81c 743a".replace(" ", ""))),

    ("4. enroll state machine: route CV2 0x59 to commit",
     bytes.fromhex("4181fda4000000 0f84fd010000".replace(" ", "")),
     bytes.fromhex("4181fd59000000 0f84160000 00".replace(" ", ""))),

    ("5. verify completion: non-zero verify status ok",
     bytes.fromhex("85d2 0f858a000000 83f801".replace(" ", "")),
     bytes.fromhex("85d2 909090909090 83f801".replace(" ", ""))),

    ("6. commit: pass Dell CV2 identity blobs",
     bytes.fromhex(
         "bf01000000 488d3563a60000 e80e02feff 4883ec08 418b7d00 "
         "4531c9 53 4531c0 31c9 31d2 6a00 4889ee 488d44241c 50"
         .replace(" ", "")),
     bytes.fromhex(
         "4883ec08 418b7d00 4c8d0d68a60000 53 41b815000000 "
         "488d0d52a60000 ba08000000 6a00 4889ee 488d44241c 50 9090"
         .replace(" ", ""))),

    ("7. commit: store Dell CV2 identity blobs in debug string",
     b"call cv_fingerprint_commit_enrollment\n"[:29],
     bytes.fromhex(
         "0000040004000000 "
         "0101ff0000000d000c42726f6164636f6d57424600"
         .replace(" ", ""))),
]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def patch_state(data, find, repl):
    """Returns 'stock', 'patched', or 'missing'."""
    n_find, n_repl = data.count(find), data.count(repl)
    if n_find == 1 and n_repl == 0:
        return "stock"
    if n_find == 0 and n_repl == 1:
        return "patched"
    return "missing"


def check(path):
    with open(path, "rb") as f:
        data = f.read()
    print("file:   " + path)
    print("sha256: " + sha256(data))
    states = [patch_state(data, find, repl) for _, find, repl in PATCHES]
    for (desc, _, _), state in zip(PATCHES, states):
        print("[%-7s] %s" % (state, desc.split(":")[0]))
    if all(s == "patched" for s in states):
        print("\nAll %d CV2 patches are applied." % len(PATCHES))
        return 0
    if all(s == "stock" for s in states):
        print("\nThis is the STOCK driver (no CV2 patches).")
        return 1
    print("\nPartially patched or unknown driver build.")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        sys.exit(check(sys.argv[2]))
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)

    with open(sys.argv[1], "rb") as f:
        data = bytearray(f.read())
    print("input sha256:  " + sha256(data))

    for desc, find, repl in PATCHES:
        assert len(find) == len(repl), "patch length mismatch: " + desc
        state = patch_state(data, find, repl)
        if state == "patched":
            print("[already] " + desc)
            continue
        if state == "missing":
            n = data.count(find)
            if n > 1:
                sys.exit("FAILED: signature ambiguous (%d hits) for patch:\n  %s" % (n, desc))
            sys.exit("FAILED: signature not found for patch:\n  " + desc +
                     "\n  (is this the right libfprint-2-tod-1-broadcom.so?)")
        off = data.index(find)
        data[off:off + len(find)] = repl
        print("[ok] " + desc)

    with open(sys.argv[2], "wb") as f:
        f.write(data)
    print("output sha256: " + sha256(data))
    print("\nPatched driver written to: " + sys.argv[2])


if __name__ == "__main__":
    main()

