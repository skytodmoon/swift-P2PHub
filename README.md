# The P2P Hub - iOS/Swift

## Introduction

> Have an idea for the next new peer-to-peer based app? This will make your life easier! Use this hub to manage connections from one iPhone to another using wifi-direct. You can easily establish new connections and transfer text data back and forth, allowing for virtually any application to be built around it. 

## Code Samples

>  You can use the included delegate API without ever changing a line of code within the hub. Simply implement the delegate protocol functions into your project.

>        protocol P2PHubDelegate: NSObjectProtocol {
            func p2pDataRecieved(data: String, hub: P2PHub, connection: inout P2PConnection)
            func p2pServerFound(serverName: String, hub: P2PHub)
            func p2pServerLost(serverName: String, hub: P2PHub)
            func p2pPeerConnected(hub: P2PHub, connection: inout P2PConnection)
            func p2pPeerDisconnected(hub: P2PHub, connection: inout P2PConnection)
        }

> Once this is done, you can spawn a new instance of P2PHub and send/receive messages.

>         let myHub: P2PHub = P2PHub(serverName: "12345", type: "_project._tcp.")
        myHub.delegate = self
        
>         func p2pPeerConnected(hub: P2PHub, connection: inout P2PConnection) {
            hub.send(message: "Hello, World!", connection: &connection)
        }

## Installation

> Installation is as easy as dropping <code>P2PHub.swift</code> into your Xcode project, then implementing it's delegate functions wherever you need to use them. 
