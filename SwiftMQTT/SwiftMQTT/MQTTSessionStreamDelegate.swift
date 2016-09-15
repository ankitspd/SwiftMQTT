//
//  MQTTSessionStreamDelegate.swift
//  SwiftMQTT
//
//  Created by Ankit Aggarwal on 12/11/15.
//  Copyright © 2015 Ankit. All rights reserved.
//

import Foundation

protocol MQTTSessionStreamDelegate {
    func streamErrorOccurred(_ stream: MQTTSessionStream)
    func receivedData(_ stream: MQTTSessionStream, data: Data, withMQTTHeader header: MQTTPacketFixedHeader)
}

class MQTTSessionStream: NSObject, StreamDelegate {
    
    internal let host: String
    internal let port: UInt16
    internal let ssl: Bool
    
    fileprivate var inputStream: InputStream?
    fileprivate var outputStream: OutputStream?
    
    internal var delegate: MQTTSessionStreamDelegate?
    
    init(host: String, port: UInt16, ssl: Bool) {
        self.host = host
        self.port = port
        self.ssl = ssl
    }
    
    func createStreamConnection() {
        Stream.getStreamsToHost(withName: host, port: NSInteger(port), inputStream: &inputStream, outputStream: &outputStream)
        inputStream?.delegate = self
        outputStream?.delegate = self
        inputStream?.schedule(in: .current, forMode: .defaultRunLoopMode)
        outputStream?.schedule(in: .current, forMode: .defaultRunLoopMode)
        inputStream?.open()
        outputStream?.open()
        if ssl {
            let level = StreamSocketSecurityLevel.negotiatedSSL
            inputStream?.setProperty(level.rawValue, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            outputStream?.setProperty(level.rawValue, forKey: Stream.PropertyKey.socketSecurityLevelKey)
        }
    }
    
    func closeStreams() {
        inputStream?.close()
        inputStream?.remove(from: .current, forMode: .defaultRunLoopMode)
        outputStream?.close()
        outputStream?.remove(from: .current, forMode: .defaultRunLoopMode)
    }
    
    func sendPacket(_ packet: MQTTPacket) -> NSInteger {
        let networkPacket = packet.networkPacket()
        if let writtenLength = outputStream?.write((networkPacket as NSData).bytes.bindMemory(to: UInt8.self, capacity: networkPacket.count), maxLength: networkPacket.count) {
            return writtenLength;
        }
        return -1
    }
    
    internal func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event(): break
        case Stream.Event.openCompleted: break
        case Stream.Event.hasBytesAvailable:
            if aStream == inputStream {
                receiveDataOnStream(aStream)
            }
        case Stream.Event.errorOccurred:
            closeStreams()
            delegate?.streamErrorOccurred(self)
        case Stream.Event.endEncountered:
            closeStreams()
        case Stream.Event.hasSpaceAvailable: break
        default:
            print("unknown")
        }
    }
    
    fileprivate func receiveDataOnStream(_ stream: Stream) {
        
        var headerByte = [UInt8](repeating: 0, count: 1)
        guard let len = inputStream?.read(&headerByte, maxLength: 1), len > 0 else { return }
        let header = MQTTPacketFixedHeader(networkByte: headerByte[0])
        
        // Max Length is 2^28 = 268,435,455 (256 MB)
        var multiplier = 1
        var value = 0
        var encodedByte: UInt8 = 0
        repeat {
            var readByte = [UInt8](repeating: 0, count: 1)
            inputStream?.read(&readByte, maxLength: 1)
            encodedByte = readByte[0]
            value += (Int(encodedByte) & 127) * multiplier
            multiplier *= 128
            if multiplier > 128*128*128 {
                return;
            }
        } while ((Int(encodedByte) & 128) != 0)
        
        let totalLength = value
        
        var responseData: Data = Data()
        if totalLength > 0 {
            var buffer = [UInt8](repeating: 0, count: totalLength)
            let readLength = inputStream?.read(&buffer, maxLength: buffer.count)
            responseData = Data(bytes: UnsafePointer<UInt8>(buffer), count: readLength!)
        }
        delegate?.receivedData(self, data: responseData, withMQTTHeader: header)
    }
}
