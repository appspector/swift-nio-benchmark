package com.appspector.websocket

import io.netty.channel.Channel
import io.netty.channel.group.DefaultChannelGroup
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame
import io.netty.util.concurrent.GlobalEventExecutor

class Dispatcher {

    private val sessions: MutableMap<String, SessionGroup> = mutableMapOf()

    fun createSessionGroup(sessionID: String, channel: Channel) {
        sessions[sessionID] = SessionGroup(channel, DefaultChannelGroup(GlobalEventExecutor.INSTANCE))
    }

    fun removeSessionGroup(sessionID: String) {
        sessions[sessionID]?.frontendChannels?.close()
    }

    fun removeFrontend(sessionID: String, channel: Channel) {
        sessions[sessionID]?.let { group ->
            channel.closeFuture()
            group.frontendChannels.remove(channel)
        }
    }

    fun joinSessionGroup(sessionID: String, channel: Channel) {
        sessions[sessionID]?.frontendChannels?.add(channel)
    }

    fun dispatchEvent(sessionID: String, payload: String) {
        sessions[sessionID]?.frontendChannels?.writeAndFlush(TextWebSocketFrame(payload))
    }
}