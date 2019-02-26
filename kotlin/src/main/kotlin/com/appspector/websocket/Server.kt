package com.appspector.websocket

import com.appspector.websocket.handler.WebSocketHandler
import io.netty.bootstrap.ServerBootstrap
import io.netty.channel.Channel
import io.netty.channel.ChannelInitializer
import io.netty.channel.ChannelOption
import io.netty.channel.EventLoopGroup
import io.netty.channel.socket.SocketChannel
import io.netty.channel.socket.nio.NioServerSocketChannel
import io.netty.handler.codec.http.HttpObjectAggregator
import io.netty.handler.codec.http.HttpServerCodec
import java.net.InetSocketAddress
import java.net.SocketAddress


class Server(private val configuration: Configuration) {

    var dispatcher = Dispatcher()

    fun listenAndWait() {
        val channel = listen()

        channel.closeFuture().await()
    }

    fun listen(): Channel {
        val bootstrap = makeBootstrap()
        val address: SocketAddress = InetSocketAddress(configuration.host, configuration.port)
        val serverChannel = bootstrap.bind(address).sync().channel()

        serverChannel.localAddress()?.let {
            print("Server running on: $it")
        }
        return serverChannel
    }

    private fun makeBootstrap(): ServerBootstrap {
        return ServerBootstrap()
            .group(configuration.eventLoopGroup)
            .channel(NioServerSocketChannel::class.java)
            .option(ChannelOption.SO_BACKLOG, configuration.backlog)
            .option(ChannelOption.SO_REUSEADDR, true)
            .childHandler(object : ChannelInitializer<SocketChannel>() {
                override fun initChannel(ch: SocketChannel) {
                    val pipeline = ch.pipeline()
                    pipeline.addLast(HttpServerCodec())
                    pipeline.addLast(HttpObjectAggregator(65536))
                    pipeline.addLast(WebSocketHandler(dispatcher, configuration.host))
                }
            })
            .childOption(ChannelOption.SO_REUSEADDR, true)
            .childOption(ChannelOption.MAX_MESSAGES_PER_READ, 1)
    }
}

data class Configuration(
    val host: String,
    val port: Int = 3000,
    val backlog: Int = 256,
    val eventLoopGroup: EventLoopGroup? = null
)