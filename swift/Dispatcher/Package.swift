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
        .package(url: "https://github.com/apple/swift-nio.git", 
                 from: "1.9.4"),
    ],

    targets: [
        .target(name: "Dispatcher", 
                dependencies: [                 
                  "NIO",
                  "NIOHTTP1",
                  "NIOWebSocket"
                ])
    ]
)
