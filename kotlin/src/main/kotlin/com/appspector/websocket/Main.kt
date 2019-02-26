package com.appspector.websocket

import io.netty.channel.nio.NioEventLoopGroup

fun main() {
    Server(
        Configuration(
            host = "0.0.0.0",
            eventLoopGroup = NioEventLoopGroup(1)
        )
    ).listenAndWait()
}