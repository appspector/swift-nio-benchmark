// swift-tools-version:4.0
//
//  Package.swift
//  Dispatcher
//
//  Created by zen on 2/23/19.
//  Copyright © 2019 AppSpector. All rights reserved.
//
import PackageDescription

let package = Package(
    name: "Dispatcher",

    dependencies: [
        /* Add your package dependencies in here
        .package(url: "https://github.com/AlwaysRightInstitute/cows.git",
                 from: "1.0.0"),
        */
        .package(url: "https://github.com/apple/swift-nio.git", 
                 from: "1.9.4"),
    ],

    targets: [
        .target(name: "Dispatcher", 
                dependencies: [
                  /* Add your target dependencies in here, e.g.: */
                  // "cows",
                  "NIO",
                  "NIOHTTP1",
                  "NIOWebSocket"
                ])
    ]
)
