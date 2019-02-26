package com.appspector.websocket.handler

import com.appspector.websocket.Dispatcher
import io.netty.channel.ChannelFuture
import io.netty.channel.ChannelHandlerContext
import io.netty.channel.SimpleChannelInboundHandler
import io.netty.handler.codec.http.*
import io.netty.handler.codec.http.websocketx.*
import io.netty.util.AttributeKey
import io.netty.util.concurrent.GenericFutureListener

class WebSocketHandler(private val dispatcher: Dispatcher, private val host: String) : SimpleChannelInboundHandler<Any>() {

    companion object {
        private val attributeSessionId = AttributeKey.newInstance<String>("sessionID")
        private val attributeClient = AttributeKey.newInstance<Client>("ws_client")
    }

    override fun channelRead0(context: ChannelHandlerContext, msg: Any) {
        when (msg) {
            is FullHttpRequest -> receivedRequest(context, msg)
            is PingWebSocketFrame -> pong(context, msg)
            is CloseWebSocketFrame -> receivedClose(context, msg)
            is TextWebSocketFrame -> receivedPayload(context, msg)
        }
    }

    private fun pong(context: ChannelHandlerContext, frame: PingWebSocketFrame) {
        context.channel().write(PongWebSocketFrame(frame.content().retain()))
    }

    private fun receivedClose(context: ChannelHandlerContext, frame:CloseWebSocketFrame ) {
        context.write(CloseWebSocketFrame(frame.statusCode(), ""))
            .addListeners(GenericFutureListener<ChannelFuture> { context.close() })
    }

    private fun receivedPayload(context: ChannelHandlerContext, frame: TextWebSocketFrame) {
        receivedPayload(context, frame.text())
    }

    private fun receivedRequest(context: ChannelHandlerContext, request: FullHttpRequest) {
        val queryStringDecoder = QueryStringDecoder(request.uri())
        val parameters = queryStringDecoder.parameters()

        val sessionID = parameters["sessionId"]?.getOrNull(0)
        if (sessionID == null) {
            context.write(DefaultFullHttpResponse(HttpVersion.HTTP_1_1, HttpResponseStatus.BAD_REQUEST))
            return
        }

        val channel = context.channel()
        channel.attr(attributeSessionId).set(sessionID)
        val wsFactory = WebSocketServerHandshakerFactory(request.uri(), null, true)
        val handshaker = wsFactory.newHandshaker(request)

        if (handshaker == null) {
            WebSocketServerHandshakerFactory.sendUnsupportedVersionResponse(channel)
        } else {
            handshaker.handshake(channel, request).await()
        }

        if (request.uri().startsWith("/create")) {
            channel.attr(attributeClient).set(Client.SDK)
            dispatcher.createSessionGroup(sessionID, channel)
            return
        }
        if (request.uri().startsWith("/join")) {
            channel.attr(attributeClient).set(Client.FRONTEND)
            dispatcher.joinSessionGroup(sessionID, channel)
            return
        }
    }

    private fun receivedPayload(context: ChannelHandlerContext, payload: String) {
        val channel = context.channel()
        val client = channel.attr(attributeClient)
        val sessionId = channel.attr(attributeSessionId)

        if (client.get() == Client.SDK) {
            dispatcher.dispatchEvent(sessionId.get(), payload)
        } else {
            print("Message from Frontend: $payload")
        }
    }

    override fun channelRegistered(context: ChannelHandlerContext) {
        val channel = context.channel()
        val client = channel.attr(attributeClient)
        val sessionId = channel.attr(attributeSessionId)

        if (client.get() == Client.FRONTEND) {
            dispatcher.joinSessionGroup(sessionId.get(), channel)
        }

        super.channelRegistered(context)
    }

    override fun channelInactive(context: ChannelHandlerContext) {
        val channel = context.channel()
        val client = channel.attr(attributeClient)
        val sessionId = channel.attr(attributeSessionId)

        if (client.get() == Client.SDK) {
            dispatcher.removeSessionGroup(sessionId.get())
        } else {
            dispatcher.removeFrontend(sessionId.get(), channel)
        }

        super.channelInactive(context)
    }

    enum class Client {
        SDK, FRONTEND
    }
}