//
//  ViewController.swift
//  WifiDirectTest
//
//  Created by Shevis Johnson on 9/26/17.
//  Copyright © 2017 VibeAnalytics. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UITextFieldDelegate, P2PHubDelegate {
    
    @IBOutlet var uiBrowser: UIButton?
    @IBOutlet var server_0: UILabel?
    @IBOutlet var server_1: UILabel?
    @IBOutlet var server_2: UILabel?
    @IBOutlet var incomingMessage: UILabel?
    
    var message: String = "Hello"
    var servers: NSMutableArray = NSMutableArray()

    
    
    var appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
    
    @IBAction func didPressBrowser(_ sender: UIButton) {
        switch sender.currentTitle! {
        case "Start Browser":
            appDelegate.p2p.startBrowser()
            sender.setTitle("Stop Browser", for: .normal)
            self.refresh(sender)
            break
        case "Stop Browser":
            appDelegate.p2p.stopBrowser()
            sender.setTitle("Start Browser", for: .normal)
            break
        default:
            break
        }
    }
    
    @IBAction func connect_0(_ sender: UIButton) {
        if (self.servers.count > 0) {
            appDelegate.p2p.initiateConnection(service: self.servers[0] as! NetService)
        }
    }
    
    @IBAction func connect_1(_ sender: UIButton) {
        if (self.servers.count > 1) {
            appDelegate.p2p.initiateConnection(service: self.servers[1] as! NetService)
        }
    }
    
    @IBAction func connect_2(_ sender: UIButton) {
        if (self.servers.count > 2) {
            appDelegate.p2p.initiateConnection(service: self.servers[2] as! NetService)
        }
    }
    
    @IBAction func refresh(_ sender: UIButton) {
        self.servers = appDelegate.p2p.services!
        if (self.servers.count > 0) {
            self.server_0?.text = (self.servers[0] as! NetService).name
        }
        if (self.servers.count > 1) {
            self.server_1?.text = (self.servers[1] as! NetService).name
        }
        if (self.servers.count > 2) {
            self.server_2?.text = (self.servers[2] as! NetService).name
        }
    }
    
    @IBAction func send(_ sender: UIButton) {
        var byteArray: [UInt8] = []
        print("message to send: \(self.message)")
        for char in self.message.characters {
            let characterString = String(char)
            let scalars = characterString.unicodeScalars
            
            byteArray.append(UInt8(scalars[scalars.startIndex].value))
        }
        for byte in byteArray {
            print("sending \(byte)")
            appDelegate.p2p.send(message: byte)
        }
    }
    
    public func textFieldDidEndEditing(_ textField: UITextField, reason: UITextFieldDidEndEditingReason) {
        self.message = textField.text!
    }
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.message = textField.text!
        self.view.endEditing(true)
        return true
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue {
            if self.view.frame.origin.y == 0{
                self.view.frame.origin.y -= keyboardSize.height
            }
        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue {
            if self.view.frame.origin.y != 0{
                self.view.frame.origin.y += keyboardSize.height
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        self.appDelegate.p2p.delegate = self
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    var buffer: String = ""
    
    public func p2pDataRecieved(data: Character) {
        self.buffer += String(data)
        self.incomingMessage?.text = self.buffer
    }
    
   // @objc func resetBuffer() {
    //    self.incomingMessage?.text = self.buffer
     //   self.buffer = ""
    //}


}

