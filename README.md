# eLinkSmart

Swift library for eLinkSmart smart padlocks over Bluetooth LE — scan, connect, log in, and unlock.

Built on [PureSwift](https://github.com/PureSwift) `Bluetooth` and `GATT`, generic over any
`CentralManager`, with a pure-Swift AES-128 implementation (no CryptoKit/CommonCrypto dependency) so it
builds on every platform. See [`Docs/BLE-Protocol.md`](Docs/BLE-Protocol.md) for the reverse-engineered
protocol.

> ⚠️ For interoperating with locks you own or are authorized to test. The lock family uses a hardcoded,
> shared AES key and a weak six-digit password; see the protocol notes.

## Usage

```swift
import GATT
import DarwinGATT
import ELinkSmart

let central = DarwinCentral()

// Scan for locks (they advertise as "lock-XXXX")
for try await scanData in central.scan(with: [.elinkSmartAdvertisedService]) {
    guard let lock = ELinkSmartLock(scanData.advertisementData) else { continue }
    print("Found \(lock.name)")

    // Connect, log in, and unlock
    let connection = try await central.connect(toLock: scanData.peripheral)
    let password = ELinkSmartPassword(rawValue: "123456")!
    try await connection.unlock(password: password)   // logs in automatically
    print("Battery: \(try await connection.readBattery())%")
    await connection.disconnect()
    break
}
```

## App

`ELinkSmart.swiftpm` is a Swift Playground iOS app that scans for locks and drives the library (log in,
unlock, read battery). In the simulator it runs against a built-in mock lock, so you can try the full flow
without hardware.

## Requirements

- Swift 6.2+
- macOS 10.15+ / iOS 13+ / watchOS 6+ / tvOS 13+

## Testing

```bash
swift test
```

The suite covers the AES-ECB cipher (against FIPS-197 vectors), the packet and framing codecs, and an
end-to-end login→unlock exchange against an in-memory simulated lock.
