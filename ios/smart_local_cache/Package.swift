// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "smart_local_cache",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "smart-local-cache", targets: ["smart_local_cache"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "smart_local_cache",
      dependencies: [],
      resources: []
    )
  ]
)
