//
//  main.swift
//  Dispatcher
//
//  Created by zen on 2/23/19.
//  Copyright © 2019 AppSpector. All rights reserved.
//

import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket

class WebSocketHandler : ChannelInboundHandler {
  
    typealias InboundIn   = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    private var awaitingClose: Bool = false
    
    var dispatcher: Dispatcher
    var sessionId: String
    
    init(dispatcher: Dispatcher, sessionId: String) {
        self.dispatcher = dispatcher
        self.sessionId = sessionId
    }

    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
      
        switch frame.opcode {
        case .connectionClose:
            self.receivedClose(ctx: ctx, frame: frame)
        case .ping:
            self.pong(ctx: ctx, frame: frame)
        case .text:
            var data = frame.unmaskedData
            let payload = data.readString(length: data.readableBytes) ?? ""
            handlePayload(ctx: ctx, payload: payload)
        default:
            return
        }
    }
    
    func handlePayload(ctx: ChannelHandlerContext, payload: String) {
        print(payload)
    }
  
    func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }
  
    func channelActive(ctx: ChannelHandlerContext) {
        print("Channel ready, client address:", ctx.channel.remoteAddress?.description ?? "-")
    }

    func channelInactive(ctx: ChannelHandlerContext) {
        print("Channel closed.", ObjectIdentifier(self))
    }
  
    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        print("ERROR:", error)
        ctx.close(promise: nil)
    }
    
    private func pong(ctx: ChannelHandlerContext, frame: WebSocketFrame) {
        var frameData = frame.data
        let maskingKey = frame.maskKey
        
        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }
        
        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, data: frameData)
        ctx.write(self.wrapOutboundOut(responseFrame), promise: nil)
    }
    
    private func receivedClose(ctx: ChannelHandlerContext, frame: WebSocketFrame) {
        // Handle a received close frame. In websockets, we're just going to send the close
        // frame and then close, unless we already sent our own close frame.
        if awaitingClose {
            // Cool, we started the close and were waiting for the user. We're done.
            ctx.close(promise: nil)
        } else {
            // This is an unsolicited close. We're going to send a response frame and
            // then, when we've sent it, close up shop. We should send back the close code the remote
            // peer sent us, unless they didn't send one at all.
            var data = frame.unmaskedData
            let closeDataCode = data.readSlice(length: 2) ?? ctx.channel.allocator.buffer(capacity: 0)
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: closeDataCode)
            _ = ctx.write(self.wrapOutboundOut(closeFrame)).map { () in
                ctx.close(promise: nil)
            }
        }
    }
}

class SDKWsHandler : WebSocketHandler {
    override func handlePayload(ctx: ChannelHandlerContext, payload: String) {
        dispatcher.dispatchEvent(sessionID: sessionId, payload: payload)
    }
    
    override func channelInactive(ctx: ChannelHandlerContext) {
        self.dispatcher.removeSessionGroup(sessionID: sessionId)
    }
}

class FrontendWsHandler : WebSocketHandler {
    override func handlePayload(ctx: ChannelHandlerContext, payload: String) {
        print("Message from Frontend \(payload)")
    }
    
    func channelRegistered(ctx: ChannelHandlerContext) {
        self.dispatcher.joinSessionGroup(sessionID: sessionId, channel: ctx.channel)
    }
    
    override func channelInactive(ctx: ChannelHandlerContext) {
        self.dispatcher.removeFrontend(sessionID: sessionId, channel: ctx.channel)
    }
}

class SessionGroup {
    let sessionChannel: Channel
    var frontendChannels: [Channel]
    
    init(sessionChannel: Channel) {
        self.sessionChannel = sessionChannel
        self.frontendChannels = []
    }
}

class Dispatcher {
    
    var sessions: [String: SessionGroup] = [:]
    
    func createSessionGroup(sessionID: String, channel: Channel) {
        sessions[sessionID] = SessionGroup(sessionChannel: channel)
    }
    
    func removeSessionGroup(sessionID: String) {
        if let group = sessions[sessionID] {
            for channel in group.frontendChannels {
                _ = channel.closeFuture
            }
        }
        
        sessions.removeValue(forKey: sessionID)
    }
    
    func removeFrontend(sessionID: String, channel: Channel) {
        if let group = sessions[sessionID] {
            channel.closeFuture.whenComplete {
                group.frontendChannels.removeAll(where: { (ch) -> Bool in
                    return !ch.isActive
                })
            }
        }
    }
    
    func joinSessionGroup(sessionID: String, channel: Channel) {
        if let group = sessions[sessionID] {
            group.frontendChannels.append(channel)
        }
    }
    
    func dispatchEvent(sessionID: String, payload: String) {
        if let group = sessions[sessionID] {
            for channel in group.frontendChannels {
                var buffer = channel.allocator.buffer(capacity: payload.utf8.count)
                buffer.write(string: payload)
                
                let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
                
                _ = channel.writeAndFlush(frame)
            }
        }
    }
}

final class Server {
  
    struct Configuration {
        var host           : String?         = nil
        var port           : Int             = 3000
        var backlog        : Int             = 256
        var eventLoopGroup : EventLoopGroup? = nil
    }
  
    let configuration  : Configuration
    let eventLoopGroup : EventLoopGroup
    var serverChannel  : Channel?
    
    var dispatcher = Dispatcher()
  
    init(configuration: Configuration = Configuration()) {
        self.configuration  = configuration
        self.eventLoopGroup = configuration.eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
  
    func listenAndWait() {
        listen()
      
        do {
            try serverChannel?.closeFuture.wait()
        }
        catch {
            print("ERROR: Failed to wait on server:", error)
        }
    }

    func listen() {
        
        let bootstrap = makeBootstrap()
      
        do {
            let address : SocketAddress
          
            if let host = configuration.host {
                address = try SocketAddress.newAddressResolving(host: host, port: configuration.port)
            } else {
                var addr = sockaddr_in()
                addr.sin_port = in_port_t(configuration.port).bigEndian
                address = SocketAddress(addr, host: "*")
            }
          
            serverChannel = try bootstrap.bind(to: address).wait()
          
            if let addr = serverChannel?.localAddress {
                print("Server running on:", addr)
            }
            else {
                print("ERROR: server reported no local address?")
            }
        }
        catch let error as NIO.IOError {
            print("ERROR: failed to start server, errno:", error.errnoCode, "\n", error.localizedDescription)
        }
        catch {
            print("ERROR: failed to start server:", type(of:error), error)
        }
    }
    
    func shouldUpgrade(head: HTTPRequestHead) -> HTTPHeaders? {
        if (head.uri.starts(with: "/create")) {
            return HTTPHeaders()
        }
        
        if (head.uri.starts(with: "/join")) {
            return HTTPHeaders()
        }
        
        return nil
    }
    
    func upgradePipelineHandler(channel: Channel, head: HTTPRequestHead) -> NIO.EventLoopFuture<Void> {
        let url = URLComponents(string: head.uri)
        let sessionIdParam = url?.queryItems?.first(where: { (item) -> Bool in
            return item.name == "sessionId"
        })
        
        guard let sessionId = sessionIdParam?.value else {
            return channel.closeFuture
        }
        
        if (head.uri.starts(with: "/create")) {
            let handler = SDKWsHandler(dispatcher: self.dispatcher, sessionId: sessionId)
            self.dispatcher.createSessionGroup(sessionID: sessionId, channel: channel)
            return channel.pipeline.add(handler: handler)
        }
        
        if (head.uri.starts(with: "/join")) {
            let handler = FrontendWsHandler(dispatcher: self.dispatcher, sessionId: sessionId)
            self.dispatcher.joinSessionGroup(sessionID: sessionId, channel: channel)
            return channel.pipeline.add(handler: handler)
        }

        return channel.closeFuture
    }

    func makeBootstrap() -> ServerBootstrap {
        let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: Int32(configuration.backlog))
            .serverChannelOption(reuseAddrOpt, value: 1)
            .childChannelInitializer { channel in
                let connectionUpgrader = WebSocketUpgrader(shouldUpgrade: self.shouldUpgrade, upgradePipelineHandler: self.upgradePipelineHandler)
                
                let config: HTTPUpgradeConfiguration = (
                    upgraders: [ connectionUpgrader ],
                    completionHandler: { _ in }
                )
                
                return channel.pipeline.configureHTTPServerPipeline(first: true, withPipeliningAssistance: true, withServerUpgrade: config, withErrorHandling: true)
                
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(reuseAddrOpt, value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      
        return bootstrap
    }
}


// MARK: - Start and run Server

let server = Server()
server.listenAndWait()
