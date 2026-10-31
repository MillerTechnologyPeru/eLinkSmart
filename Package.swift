// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ELinkSmart",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "ELinkSmart",
            targets: ["ELinkSmart"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Bluetooth.git",
            from: "8.2.0"
        ),
        .package(
            url: "https://github.com/PureSwift/GATT.git",
            from: "4.1.0"
        ),
    ],
    targets: [
        .target(
            name: "ELinkSmart",
            dependencies: [
                .product(
                    name: "Bluetooth",
                    package: "Bluetooth"
                ),
                .product(
                    name: "GATT",
                    package: "GATT"
                ),
            ]
        ),
        .testTarget(
            name: "ELinkSmartTests",
            dependencies: [
                "ELinkSmart",
                .product(
                    name: "BluetoothGAP",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothHCI",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(
                    name: "BluetoothGATT",
                    package: "Bluetooth",
                    condition: .when(platforms: [.macOS, .linux])
                )
            ]
        ),
    ]
)
