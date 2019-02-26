package com.appspector.websocket

import io.netty.channel.Channel
import io.netty.channel.group.ChannelGroup

data class SessionGroup(val sessionChannel: Channel, val frontendChannels: ChannelGroup)