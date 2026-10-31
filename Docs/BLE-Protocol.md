# eLinkSmart Padlock BLE Protocol

Reverse-engineering notes for the eLinkSmart smart padlock family. Each fact is labeled:

- **Verified** — confirmed against a first-hand BLE capture of a real lock (model P5BF-PG) and reproduced by this library's tests.
- **Observed** — seen in one source (a capture or write-up) but not independently cross-checked.
- **Unknown** — not yet understood.

> Sources: a PacketLogger capture of a real eLinkSmart lock decrypted with the key below; the Reversec
> write-up *"Multiple vulnerabilities in eLinkSmart padlocks"*
> (<https://labs.reversec.com/posts/2024/02/multiple-vulnerabilities-in-elinksmart-padlocks>); and the
> BLESPloit `device-library` eLinkSmart profile (`products/elinksmart_lock/`).

## GATT layout — Verified

The real lock negotiates an **MTU of 512** and exposes three services:

| Role | UUID | Handles | Notes |
|------|------|---------|-------|
| Generic Access | `0x1800` | 0x0001–0x0005 | Standard. Device name `lock`. |
| Lock service | `0x1828` | 0x0006–0x000d | Vendor reuses the SIG "Fitness Machine" short UUID. |
| Nordic DFU | `0xFE59` | 0x000e–0x0016 | Firmware-update service. |

Lock-service characteristics:

| Name | UUID | Value handle | Properties |
|------|------|--------------|-----------|
| `CHR_DATAIN` | `0x2ADD` | 0x0008 | **Write Without Response** (`0x04`) — app → lock command stream |
| `CHR_DATAOUT` | `0x2ADE` | 0x000a | Notify (`0x10`) — lock → app replies |
| `CHR_DATAIN2` | `0x2ADF` | 0x000d | Write (`0x08`) — secondary, unused in the capture |

> **No battery service.** There is no `0x180F` on the real unit, so battery is not a GATT read (the
> library does not expose a battery API). The login reply carries device info including a `0x64` (= 100)
> byte that is a likely battery-percent field; decoding it is a future task.

## Advertisement — Verified

- Complete Local Name `lock-XXXX`, where `XXXX` is the last two octets of the Bluetooth address in hex
  (address `24:EC:4A:30:79:6A` → `lock-796A`).
- Incomplete 16-bit service UUID list contains `0xFF30` (**not** the GATT service `0x1828`); scan filtering
  uses `0xFF30`.
- Manufacturer Specific Data begins `01 0c`, then the 6-octet Bluetooth address reversed. **Observed.**

## Encryption — Verified

- **AES-128 in ECB mode.** No IV. Ciphertext length is always a multiple of 16.
- The 16-byte key is the ASCII bytes of `"7b7079bb69001dce"`
  (`37 62 37 30 37 39 62 62 36 39 30 30 31 64 63 65`), hardcoded in the app and firmware.
- Plaintext not on a 16-byte boundary is **PKCS7**-padded before encryption. Decryption can ignore the
  padding, because the payload carries its own length field.

## Frame format (decrypted) — Verified

Little-endian throughout:

```
[ payload length : UInt16 ] [ command : UInt16 ] [ parameters ... ]
```

`payload length` counts the bytes after itself (`2 + parameters.count`). Trailing padding is ignored.

| Exchange | Decrypted plaintext | Meaning |
|----------|---------------------|---------|
| Login request | `06 00 01 00 <nonce:4>` | len 6, cmd `0x01`; the nonce is a Unix timestamp |
| Login reply | `46 00 01 00 <token:4> <device info…>` | len 70, cmd `0x01`, 4-byte session token, then model/config |
| Unlock request | `10 00 12 00 <proof:4> <timestamp:4> <password:6>` | len 16, cmd `0x12`; password is 6 ASCII digits |
| Acknowledgement | `04 00 <cmd> 00 00 00` | len 4, echoes the command code |

The **proof** is the first four bytes of `AES-ECB(challenge)`, where the challenge is the 4-byte token
from the login reply, PKCS7-padded to one block before encryption. Every authenticated command (unlock
and the management commands) carries this proof, not the raw challenge. **Verified** against the capture:
challenge `FE 12 00 00` → proof `7D 2E BC FB`.

## BLE framing — Verified

- **App → lock** (write to `0x2ADD`, Write Without Response): first packet is
  `[ nibble-swapped packet count ] [ 0x00 ]` followed by ciphertext; the stream is cut into ≤20-byte
  writes. The smallest `n` with `n*20 - 2 >= ciphertext.count` is the count, so a single 16-byte block is
  `10 00 …`, a 32-byte (two-block) frame is `20 00 …` split 18 + 14, three blocks `30 00 …`, and so on.
  (The app chunks to ≤20 bytes even though the MTU is 512.)
- **Lock → app** (notifications on `0x2ADE`): `[ LE16 ciphertext length ] [ ciphertext ]`. With the large
  MTU the whole reply usually arrives in one notification; longer replies continue in ≤20-byte packets.

## Commands — Verified / Observed

Correlated with the vendor app UI from a screen recording of the same session:

| Code | Meaning | Status |
|------|---------|--------|
| `0x01` | Login / challenge → session token + device info | Verified |
| `0x03` | Verify admin password (precedes management actions) | Observed |
| `0x0a` | **List users / fingerprints** (paged by index; large record table) | Observed |
| `0x12` | Unlock | Verified |
| `0x16` | Add / rename a user (writes the name) | Observed |
| `0x21` | Get one user / record (returns a name) | Observed |
| `0x22` | Get count / status | Observed |
| other (1–43) | Fingerprint enrollment, history, settings, factory reset | Unknown |

After a successful command the lock replies with the acknowledgement above; a wrong password or token
gets **no reply**. After ten wrong passwords the lock locks out logins for ~90 seconds (**Observed**).

## Authentication flow — Verified

1. Enable notifications on `0x2ADE` (write `01 00` to its CCCD).
2. Write **login** (`0x01`). The lock replies with a 4-byte challenge token (plus device info).
3. Write **unlock** (`0x12`) with the challenge proof, a timestamp, and the six-digit password.
4. The lock acknowledges by echoing the command. Management commands reuse the same proof.

## Password — Verified

- Exactly six decimal digits, sent as ASCII.
- Persists through factory resets; the app cannot change it and fetches it from the vendor's web API. This
  library takes it from the caller.

## Security notes

The hardcoded, shared AES key plus a weak, non-changeable six-digit password mean traffic can be decrypted
and commands forged by anyone with the key. This library is for interoperating with locks you own or are
authorized to test; do not use it against locks you do not control.
