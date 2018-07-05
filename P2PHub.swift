//
//  P2PHub.swift
//
//  Created by Shevis Johnson on 10/14/17.
//  Copyright © 2017 Vibe Analytics, LLC. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import UIKit
import CoreData

protocol P2PHubDelegate: NSObjectProtocol {
    func p2pDataRecieved(data: String, hub: P2PHub, connection: inout P2PConnection)
    func p2pServerFound(serverName: String, hub: P2PHub)
    func p2pServerLost(serverName: String, hub: P2PHub)
    func p2pPeerConnected(hub: P2PHub, connection: inout P2PConnection)
    func p2pPeerDisconnected(hub: P2PHub, connection: inout P2PConnection)
}

public class P2PConnection: NSObject {
    var inputStream: InputStream?
    var outputStream: OutputStream?
    var streamOpenCount: Int = 0
    var hasSpaceAvailable: Bool = false
    var connected: Bool = false
    var ID: String?
    init(input_stream: InputStream, output_stream: OutputStream, ident: String) {
        inputStream = input_stream
        outputStream = output_stream
        ID = ident
    }
    override init() {
        super.init()
        inputStream = nil
        outputStream = nil
        ID = ""
    }
}

public class P2PHub: NSObject, NetServiceDelegate, StreamDelegate, NetServiceBrowserDelegate {
    public var registeredName: String?
    public var services: NSMutableArray?
    public var connectedToServer: Bool? // logic not implemented yet
    public var connectedToClient: Bool? // ...
    weak var delegate: P2PHubDelegate?
    
    private var server: NetService?
    private var isServerStarted: Bool?
    private var browser: NetServiceBrowser?
    private var initiator: Bool?
    
    public var p2pConnections: [P2PConnection] = []
    public var numConnections: Int = 0
    private var idxInUse: Int = -1
    
    private var overflowInputStreams: [InputStream] = []
    private var overflowOutputStreams: [OutputStream] = []
    
    private var server_type: String = ""
    
    init(serverName: String, type: String) {
        super.init()
        self.server_type = type
        
        self.server = NetService(domain: "local.", type:  type, name: serverName, port: 0)
        self.server!.includesPeerToPeer = true
        self.server!.delegate = self
        
        self.isServerStarted = false
        //self.streamOpenCount = 0
        //self.streamHasSpaceAvailable = true
        self.services = NSMutableArray()
    }
    
    // ---------------------- Server -----------------------
    
    public func startServer() {
        assert(!self.isServerStarted!)
        
        self.server!.publish(options: .listenForConnections)
        self.server!.delegate = self
        self.isServerStarted = true
        print("boradcasting service as \(self.server!.name)")
    }
    
    public func stopServer() {
        self.server!.stop()
        self.registeredName = nil
        self.isServerStarted = false
    }
    
    
    public func restartServer() {
        if (self.isServerStarted!) {
            self.stopServer()
        }
        
        // close streams
        
        self.startServer()
    }
    
    public func renameServer(name: String) {
        var was = false
        if self.isServerStarted! {
            self.stopServer()
            was = true
        }
        self.server = NetService(domain: "local.", type:  self.server_type, name: name, port: 0)
        self.server!.includesPeerToPeer = true
        self.server!.delegate = self
        if was {
            self.startServer()
        }
    }
    
    public func netServiceDidPublish(_ sender: NetService) {
        assert(sender == self.server)
        self.registeredName = self.server!.name
    }
    
    public func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
        OperationQueue.main.addOperation({
            assert(sender == self.server)
            print ("connection from client recieved")
            let timest = arc4random_uniform(100000)
            self.p2pConnections.append(P2PConnection(input_stream: inputStream, output_stream: outputStream, ident: String(timest)))
            self.numConnections = self.p2pConnections.count
            self.openStreams(connection: &self.p2pConnections[self.p2pConnections.count-1])
        })
    }
    
    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        // This is called when the server stops of its own accord.  The only reason
        // that might happen is if the Bonjour registration fails when we reregister
        // the server, and that's hard to trigger because we use auto-rename.  I've
        // left an assert here so that, if this does happen, we can figure out why it
        // happens and then decide how best to handle it.
        print("did not publish")
        assert(sender == self.server)
        assert(false)
    }
    
    
    // ----------------------- Listener ------------------------
    
    public func startBrowser() {
        assert(self.services!.count == 0)
        assert(self.browser == nil)
        
        self.browser = NetServiceBrowser()
        self.browser!.includesPeerToPeer = true
        self.browser!.delegate = self
        self.browser!.searchForServices(ofType: self.server_type, inDomain: "local")
    }
    
    public func stopBrowser() {
        self.browser?.stop()
        self.browser = nil
        
        self.services?.removeAllObjects()
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        assert(browser == self.browser)
        
        if (!self.isServerStarted! || self.server! != service) {
            self.services!.add(service)
            print("Service found: \(service.name)")
            self.delegate?.p2pServerFound(serverName: service.name, hub: self)
        }
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if (self.services!.contains(service)) {
            self.services!.remove(service)
            print("Service lost: \(service.name)")
            self.delegate?.p2pServerLost(serverName: service.name, hub: self)
        }
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        assert(browser == self.browser)
        assert(false)
    }
    
    // --------------------- Connection -----------------------
    
    var charArray: [Character] = []
    var counter: Int = 0
    func bufferMessage(char: Character?, connection: inout P2PConnection) {
        counter += 1
        //print("message_buffer_recieved: \(counter)")
        if let thisChar: Character = char {
            charArray.append(thisChar)
        }
        if counter == 128 {
            var mess = String(charArray)
            mess = mess.replacingOccurrences(of: "\0", with: "", options: NSString.CompareOptions.literal, range: nil)
            print("message recieved: \(mess)")
            self.delegate?.p2pDataRecieved(data: mess, hub: self, connection: &connection)
            charArray = []
            counter = 0
        }
    }
    
    // connection management
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        
        var connectionIdx: Int = -1
        var foundConnection: Bool = false
        for i: Int in 0...p2pConnections.count-1 {
            if aStream == p2pConnections[i].inputStream {
                connectionIdx = i
                self.idxInUse = i
                foundConnection = true
                break
            }
            if aStream == p2pConnections[i].outputStream {
                connectionIdx = i
                self.idxInUse = i
                foundConnection = true
                break
            }
        }
        if !foundConnection {
            print("recieved erroneous connection in stream function")
            return
        }
        
        switch (eventCode) {
        case Stream.Event.openCompleted:
            p2pConnections[connectionIdx].streamOpenCount += 1
            if (p2pConnections[connectionIdx].streamOpenCount <= 2) {
                if aStream == p2pConnections[connectionIdx].inputStream {
                    print("input stream opened")
                } else {
                    print("output stream opened")
                }
                
                if (p2pConnections[connectionIdx].streamOpenCount == 2) {
                    // handle individual communication configuration
                    print("both streams open")
                }
            } else {
                if let oStream: OutputStream = aStream as? OutputStream {
                    print("overflow recieved. must be an error")
                    p2pConnections[connectionIdx].streamOpenCount -= 1
                }
            }
            break
        case Stream.Event.hasSpaceAvailable:
            //allow messages to be sent if this is outputStream
            if (aStream == p2pConnections[connectionIdx].outputStream) {
                self.p2pConnections[connectionIdx].hasSpaceAvailable = true
                if (self.p2pConnections[connectionIdx].connected == false) {
                    self.p2pConnections[connectionIdx].connected = true
                    self.delegate?.p2pPeerConnected(hub: self, connection: &p2pConnections[connectionIdx])
                }
            }
            break
        case Stream.Event.hasBytesAvailable:
            let count = 1
            var b = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            b.initialize(to: 0, count: count)
            defer {
                b.deinitialize(count: count)
                b.deallocate(capacity: count)
            }
            b.pointee = UInt8()
            
            var bytesRead: NSInteger
            
            assert(aStream == p2pConnections[connectionIdx].inputStream)
            
            bytesRead = p2pConnections[connectionIdx].inputStream!.read(&b.pointee, maxLength: MemoryLayout<UInt8>.size)
            
            if (bytesRead <= 0) {
                // Do nothing; we'll handle EOF and error in the
                // NSStreamEventEndEncountered and NSStreamEventErrorOccurred case,
                // respectively.
            } else {
                //print(bytesRead)
                //print(b)
                if self.delegate != nil {
                    self.bufferMessage(char: uint8char(input: b.pointee), connection: &p2pConnections[connectionIdx])
                }
                // parse byte data as needed (assign each sudent a class-local ID upon registration)
            }
            
            break
        case Stream.Event.errorOccurred:
            break
        case Stream.Event.endEncountered:
            print("end encountered")
            self.delegate?.p2pPeerDisconnected(hub: self, connection: &p2pConnections[connectionIdx])
            break
        default:
            assert(false)
        }
        self.idxInUse = -1
    }
    
    func openStreams(connection: inout P2PConnection) {
        assert(connection.inputStream != nil);           // streams must exist but aren't open
        assert(connection.outputStream != nil)
        assert(connection.streamOpenCount == 0)
        
        connection.inputStream!.delegate = self
        connection.inputStream!.schedule(in: .current, forMode: .defaultRunLoopMode)
        connection.inputStream!.open()
        
        connection.outputStream!.delegate = self
        connection.outputStream!.schedule(in: .current, forMode: .defaultRunLoopMode)
        connection.outputStream!.open()
    }
    
    func closeStream(connection: inout P2PConnection) {
        assert( (connection.inputStream != nil) == (connection.outputStream != nil) )
        if (connection.inputStream != nil) {
            connection.inputStream!.remove(from: .current, forMode: .defaultRunLoopMode)
            connection.inputStream!.close()
            connection.inputStream = nil
            
            connection.outputStream!.remove(from: .current, forMode: .defaultRunLoopMode)
            connection.outputStream!.close()
            connection.outputStream = nil
        }
        connection.streamOpenCount = 0
    }
    
    public func send(message: String, connection: inout P2PConnection) throws -> Bool {
        print("sending message: \(message)")
        //assert(self.streamOpenCount == 2)
        var byteArray: [UInt8] = []
        for char in message.characters {
            let characterString = String(char)
            let scalars = characterString.unicodeScalars
            
            byteArray.append(UInt8(scalars[scalars.startIndex].value))
            if byteArray.count == 128 {
                break;
            }
        }
        while byteArray.count < 128 {
            byteArray.append(UInt8(0))
        }
        
        // Only write to the stream if it has space available, otherwise we might block.
        // In a real app you have to handle this case properly but in this sample code it's
        // OK to ignore it; if the stream stops transferring data the user is going to have
        // to tap a lot before we fill up our stream buffer (-:
        if !(connection.hasSpaceAvailable) {
            return false
        }
        for byte in byteArray {
            if (connection.hasSpaceAvailable) {
                let count = 1
                var pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
                pointer.initialize(repeating: 0, count: count)
                defer {
                    pointer.deinitialize(count: count)
                    pointer.deallocate(capacity: count)
                }
                pointer.pointee = byte
                let bytesWritten: NSInteger = connection.outputStream!.write(&pointer.pointee, maxLength: MemoryLayout<UInt8>.size)
                if (bytesWritten != MemoryLayout.size(ofValue: pointer.pointee)) {
                    print("something went wrong")
                    self.restartServer()
                }
            } else {
                print("stream doesn't have space")
            }
        }
        return true
    }
    
    func broadcast(message: String) {
        let intArray: [Int] = Array(0...self.numConnections-1)
        for i in intArray {
            do {
                if i != self.idxInUse {
                    try self.send(message: message, connection: &self.p2pConnections[i])
                }
            } catch {
                print("didn't send to p\(i)")
            }
        }
    }
    
    func initiateConnection(service: NetService) {
        var success: Bool
        
        p2pConnections.append(P2PConnection())
        self.numConnections = self.p2pConnections.count
        success = service.getInputStream(&p2pConnections[p2pConnections.count-1].inputStream, outputStream: &p2pConnections[p2pConnections.count-1].outputStream)
        if (!success) {
            self.restartServer()
            print("connection failed")
        } else {
            print("connection success")
            self.openStreams(connection: &p2pConnections[p2pConnections.count-1])
        }
    }
    
    func closeConnection(connection: inout P2PConnection) {
        connection.connected = false
        self.closeStream(connection: &connection)
    }
    
    func uint8char(input: UInt8) -> Character {
        return Character(UnicodeScalar(input))
    }
}

/*extension UInt8 {
    var char: Character {
        return Character(UnicodeScalar(self))
    }
}*/

