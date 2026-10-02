// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "smart_local_storage",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "smart-local-storage", targets: ["smart_local_storage"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "smart_local_storage",
      dependencies: [],
      resources: []
    )
  ]
)
