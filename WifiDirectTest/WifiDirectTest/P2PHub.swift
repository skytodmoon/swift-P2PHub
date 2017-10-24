//
//  P2PHub.swift
//  WifiDirectTest
//
//  Created by Shevis Johnson on 10/14/17.
//  Copyright © 2017 Vibe Analytics, LLC. All rights reserved.
//

import Foundation
import UIKit
import CoreData

protocol P2PHubDelegate: NSObjectProtocol {
    func p2pDataRecieved(data: Character)
}

public class P2PHub: NSObject, NetServiceDelegate, StreamDelegate, NetServiceBrowserDelegate {
    public var registeredName: String?
    public var services: NSMutableArray?
    public var connectedToServer: Bool? // logic not implemented yet
    public var connectedToClient: Bool? // ...
    weak var delegate: P2PHubDelegate?
    
    private var server: NetService?
    private var isServerStarted: Bool?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var streamOpenCount: UInt?
    private var streamHasSpaceAvailable: Bool?
    private var browser: NetServiceBrowser?
    private var initiator: Bool?


    init(serverName: String) {
        super.init()
        self.server = NetService(domain: "local.", type:  "_WDTest._tcp.", name: serverName, port: 0)

        self.server!.includesPeerToPeer = true
        self.server!.delegate = self
        self.isServerStarted = false
        self.streamOpenCount = 0
        self.streamHasSpaceAvailable = true
        self.services = NSMutableArray()
    }

    // ---------------------- Server -----------------------
    
    public func startServer() {
        assert(!self.isServerStarted!)
        self.server!.publish(options: .listenForConnections)
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

    public func netServiceDidPublish(_ sender: NetService) {
        assert(sender == self.server)
        self.registeredName = self.server!.name
    }

    public func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
        OperationQueue.main.addOperation({
            assert(sender == self.server)

            assert( (self.inputStream != nil) == (self.outputStream != nil) )      // should either have both or neither
            
            print ("connection from client recieved")

            if (self.inputStream != nil) {
                // We already have a connection in place; reject this new one.
                inputStream.open()
                inputStream.close()
                outputStream.open()
                outputStream.close()
            } else {
                // restart server.  Start by deregistering the server, to discourage
                // other folks from connecting to us (and being disappointed when we reject
                // the connection).

                self.server!.stop()
                self.isServerStarted = false
                self.registeredName = nil
                

                // Latch the input and output sterams and kick off an open.

                self.inputStream  = inputStream
                self.outputStream = outputStream

                self.openStreams()
            }
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
        self.browser!.searchForServices(ofType: "_WDTest._tcp.", inDomain: "local")
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
        }
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if (self.services!.contains(service)) {
            self.services!.remove(service)
            print("Service lost: \(service.name)")
        }
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        assert(browser == self.browser)
        assert(false)
    }
    
    // --------------------- Connection -----------------------
    
    
    // connection management
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch (eventCode) {
        case Stream.Event.openCompleted:
            self.streamOpenCount! += 1
            assert(self.streamOpenCount! <= 2)
            if aStream == self.inputStream {
                print("input stream opened")
            } else {
                print("output stream opened")
            }
            
            if (self.streamOpenCount == 2) {
                // handle individual communication configuration
                
                self.stopServer()
            }
            
            break
        case Stream.Event.hasSpaceAvailable:
            assert(aStream == self.outputStream)
            //self.streamHasSpaceAvailable = true
            // allow messages to be sent if this is outputStream
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
            
            assert(aStream == self.inputStream)
            
            bytesRead = self.inputStream!.read(&b.pointee, maxLength: MemoryLayout<UInt8>.size)
            
            if (bytesRead <= 0) {
                // Do nothing; we'll handle EOF and error in the
                // NSStreamEventEndEncountered and NSStreamEventErrorOccurred case,
                // respectively.
            } else {
                //print(bytesRead)
                //print(b)
                if self.delegate != nil {
                    if (b.pointee.char >= "A") && (b.pointee.char <= "Z") {
                        self.delegate!.p2pDataRecieved(data: b.pointee.char)
                    } else if (b.pointee.char >= "a") && (b.pointee.char <= "z") {
                        self.delegate!.p2pDataRecieved(data: b.pointee.char)
                    } else {
                        
                    }
                }
                // parse byte data as needed (assign each sudent a class-local ID upon registration)
            }
            
            break
        case Stream.Event.errorOccurred:
            break
        case Stream.Event.endEncountered:
            print("end encountered")
            self.restartServer()
            break
        default:
            assert(false)
        }
    }
    
    func openStreams() {
        assert(self.inputStream != nil);           // streams must exist but aren't open
        assert(self.outputStream != nil)
        assert(self.streamOpenCount == 0)
        
        self.inputStream!.delegate = self
        self.inputStream!.schedule(in: .current, forMode: .defaultRunLoopMode)
        self.inputStream!.open()
        
        self.outputStream!.delegate = self
        self.outputStream!.schedule(in: .current, forMode: .defaultRunLoopMode)
        self.outputStream!.open()
    }
    
    func closeStream() {
        assert( (self.inputStream != nil) == (self.outputStream != nil) )
        if (self.inputStream != nil) {
            self.inputStream!.remove(from: .current, forMode: .defaultRunLoopMode)
            self.inputStream!.close()
            self.inputStream = nil
            
            self.outputStream!.remove(from: .current, forMode: .defaultRunLoopMode)
            self.outputStream!.close()
            self.outputStream = nil
        }
        self.streamOpenCount = 0
    }
    
    public func send(message: UInt8) {
        print(self.streamOpenCount!)
        assert(self.streamOpenCount == 2)
        
        // Only write to the stream if it has space available, otherwise we might block.
        // In a real app you have to handle this case properly but in this sample code it's
        // OK to ignore it; if the stream stops transferring data the user is going to have
        // to tap a lot before we fill up our stream buffer (-:
        
        if (self.outputStream!.hasSpaceAvailable) {
            let count = 1
            var pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            pointer.initialize(to: 0, count: count)
            defer {
                pointer.deinitialize(count: count)
                pointer.deallocate(capacity: count)
            }
            pointer.pointee = message
            let bufferPointer = UnsafeBufferPointer(start: pointer, count: count)
            for (index, value) in bufferPointer.enumerated() {
                print("message \(index): \(value)")
            }
            let bytesWritten: NSInteger = self.outputStream!.write(&pointer.pointee, maxLength: MemoryLayout<UInt8>.size)
            if (bytesWritten != MemoryLayout.size(ofValue: pointer.pointee)) {
                print("something went wrong")
                self.restartServer()
            }
        }
    }
    
    func initiateConnection(service: NetService) {
        var success: Bool
        var inStream: InputStream?
        var outStream: OutputStream?
        success = service.getInputStream(&inStream, outputStream: &outStream)
        if (!success) {
            self.restartServer()
            print("connection failed")
        } else {
            print("connection success")
            self.inputStream = inStream
            self.outputStream = outStream
            self.openStreams()
        }
    }
    
    func closeConnection() {
        self.closeStream()
    }
}

extension UInt8 {
    var char: Character {
        return Character(UnicodeScalar(self))
    }
}
