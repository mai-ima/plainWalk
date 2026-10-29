// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "PlainWalkPlaygrounds",
    defaultLocalization: "ja",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "PlainWalkPlaygrounds",
            targets: ["AppModule"],
            bundleIdentifier: "org.example.plainwalk.playgrounds",
            displayVersion: "0.3.0",
            bundleVersion: "3",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait, .landscapeRight, .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .healthcareFitness,
            additionalInfoPlistContentFilePath: "AppInfo.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            resources: [
                .copy("Resources/Web"),
                .process("Resources/Assets.xcassets"),
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [.define("PLAYGROUNDS")]
        )
    ]
)
