# eLinkSmart Padlock BLE Protocol

Reverse-engineering notes for the eLinkSmart smart padlock family. Each fact is labeled:

- **Verified** — confirmed against the published write-ups and the BLESPloit device profile, and exercised by this library's tests.
- **Observed** — reported by one source; plausible but not independently confirmed here.
- **Unknown** — not yet understood.

> Sources: the Reversec write-up *"Multiple vulnerabilities in eLinkSmart padlocks"*
> (<https://labs.reversec.com/posts/2024/02/multiple-vulnerabilities-in-elinksmart-padlocks>) and the BLESPloit
> `device-library` eLinkSmart profile (`products/elinksmart_lock/`). The UUIDs and key below come from the
> BLESPloit profile, which mirrors the real device; correct them against a first-hand capture of your unit.

## GATT layout — Verified

| Role | UUID | Properties | Notes |
|------|------|-----------|-------|
| Primary service | `0x1828` | — | Vendor reuses the SIG "Fitness Machine" short UUID. |
| Data-in (`CHR_DATAIN`) | `0x2ADD` | Write | App → lock encrypted command stream (chunked). |
| Data-out (`CHR_DATAOUT`) | `0x2ADE` | Notify | Lock → app encrypted replies (chunked). |
| Data-in 2 (`CHR_DATAIN2`) | `0x2ADF` | Write | Secondary write characteristic, usually unused. |
| Battery service | `0x180F` | — | Standard SIG battery service. |
| Battery level | `0x2A19` | Read / Notify | Percentage, one byte. |

## Advertisement — Verified

- Complete Local Name `lock-XXXX`, where `XXXX` is the last two octets of the Bluetooth address in hex
  (e.g. address `24:EC:4A:30:79:6A` → `lock-796A`).
- Incomplete 16-bit service UUID list contains `0xFF30` (note: **not** the GATT service `0x1828`). Scan filtering
  uses `0xFF30`.
- Manufacturer Specific Data begins `01 0c`, followed by the 6-octet Bluetooth address reversed. **Observed.**

## Encryption — Verified

- **AES-128 in ECB mode.** No IV. Ciphertext length is always a multiple of 16.
- The 16-byte key is hardcoded in the app and firmware: the ASCII bytes of `"7b7079bb69001dce"`
  (`37 62 37 30 37 39 62 62 36 39 30 30 31 64 63 65`).
- Plaintext shorter than a block boundary is **PKCS7**-padded before encryption. Decryption tolerates either
  PKCS7 or zero padding, because the payload carries its own length field.

## Frame format (decrypted) — Verified

Little-endian throughout:

```
[ payload length : UInt16 ] [ command : UInt16 ] [ parameters ... ]
```

`payload length` counts the bytes after itself, i.e. `2 + parameters.count`. Trailing padding is ignored.

| Exchange | Plaintext | Meaning |
|----------|-----------|---------|
| Login request | `06 00 01 00 D3 F1 50 65` | len 6, cmd `0x01`, 4-byte nonce |
| Login reply | `30 00 01 00 <challenge:4> <tail:42>` | len 48, cmd `0x01`, 4-byte session token, padded to 64 B |
| Unlock request | `10 00 12 00 <token:4> <timestamp:4> <password:6>` | len 16, cmd `0x12` |
| Acknowledgement | `04 00 <cmd> 00 00 00` | len 4, echoes the command |

## BLE framing (chunking) — Verified

BLE packets are at most 20 bytes, so a frame larger than one packet is split.

- **App → lock** (write to `0x2ADD`): the first packet is `[ nibble-swapped packet count ] [ 0x00 ]` followed by
  ciphertext; the whole stream is cut into ≤20-byte writes. `packet count` is the smallest `n` with
  `n*20 - 2 >= ciphertext.count`. A single 16-byte block therefore starts `10 00 …`
  (one packet → nibble-swap of `0x01` is `0x10`).
- **Lock → app** (notifications on `0x2ADE`): the first notification is a little-endian `UInt16` ciphertext
  length followed by up to 18 ciphertext bytes; later notifications carry up to 20 raw bytes each. Reassemble,
  then AES-ECB decrypt.

## Commands — partially Verified

| Code | Name | Status |
|------|------|--------|
| `0x01` | Login / challenge | Verified |
| `0x04` | Unlock (alternate) | Observed |
| `0x12` | Unlock | Verified |
| `0x0C` | Factory reset | Observed |
| `0x01`–`0x2B` | Full command set (1–43) | Unknown |

## Authentication flow — Verified

1. Subscribe to notifications on `0x2ADE`.
2. Write the **login** command (`0x01`). The lock replies with a random 4-byte session token.
3. Write the **unlock** command (`0x12`) carrying the session token, a timestamp, and the six-digit password.
4. The lock replies with an **acknowledgement** that echoes the command. A wrong password or token gets **no
   reply** (the lock stays silent). After ten wrong passwords the lock locks out logins for ~90 seconds.

## Password — Verified

- Exactly six decimal digits, sent as ASCII.
- Persists through factory resets; the app cannot change it and retrieves it from the vendor's web API. This
  library takes it from the caller instead. The BLESPloit profile's default is `123456`.

## Open questions — Unknown

- The meaning of the two header shorts beyond "length" and "command" in some variants.
- The remaining command codes (fingerprint enrollment, settings, status), and whether `0x04` vs `0x12` differ
  by firmware revision.
- Whether the real device uses Write or Write-Without-Response on `0x2ADD` (the profile lists Write).

## Security notes

The hardcoded, shared AES key and the weak, non-changeable six-digit password mean traffic can be decrypted and
commands forged by anyone with the key. This library is for interoperating with locks you own or are authorized
to test; do not use it against locks you do not control.
