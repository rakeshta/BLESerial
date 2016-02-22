//
//  BLESerialPeripheral.swift
//  BLE Smart Car Remote
//
//  Created by Rakesh TA on 20/02/2016.
//  Copyright © 2016 Raptor Soft. All rights reserved.
//

import Foundation
import CoreBluetooth
import CocoaLumberjackSwift


// MARK: - BLESerialPeripheralDelegate

/// The `BLESerialPeripheralDelegate` protocol defines methods that must be adopted
/// to be notified of connection, data events etc.
@objc
public protocol BLESerialPeripheralDelegate: AnyObject {
    
    // MARK: - Connection Events
    
    /// Invoked when a connection is succesfully created with the peripheral.
    ///
    /// - parameter serialPeripheral: The peripheral that has been connected.
    optional func serialPeripheralDidConnect(serialPeripheral: BLESerialPeripheral)
    
    /// Invoked when an existing connection to a peripheral is torn down.
    ///
    /// - parameter serialPerihperal: The peripheral that was disconnected.
    /// - parameter error:            The cause of the failure if any.
    optional func serialPeripheral(serialPerihperal: BLESerialPeripheral, didDisconnectWithError error: NSError?)
    
    /// Invoked when a connection could not be established with the peripheral.
    ///
    /// - parameter serialPerihperal: The peripheral that failed to connect.
    /// - parameter error:            The cause of the failure.
    optional func serialPeripheral(serialPerihperal: BLESerialPeripheral, didFailToConnectWithError error: NSError?)
    
    
    // MARK: - Data
    
    /// Invoked when data is received from the peripheral.
    ///
    /// - parameter serialPerihperal: The peripheral that sent the data.
    /// - parameter length:           The length of data that was received.
    optional func serialPeripheral(serialPerihperal: BLESerialPeripheral, didReceiveBytes length: Int)
    
    
    // MARK: - Meta Events
    
    /// Invoked when the peripheral's name changes
    ///
    /// - parameter serialPerihperal: The peripheral that changed its name.
    /// - parameter name:             The new name of the peripheral.
    optional func serialPeripheral(serialPerihperal: BLESerialPeripheral, didUpdateName name: String?)
}


// MARK: - BLESerialPeripheral

/// `BLESerialPeripheral` is a thin wrapper around a CoreBluetooth peripheral
/// that supports serial communication.
/// 
/// - seealso: `BLESerialManager`
public final class BLESerialPeripheral: NSObject {
    
    // MARK: - Members
    
    private  let serialManager:          BLESerialManager
    
    internal let cbPeripheral:           CBPeripheral
    
    private  let advertisementData:     [String: AnyObject]
    
    private  var serialCharacteristic:   CBCharacteristic? {
        didSet {
            if  let ch = oldValue where ch.isNotifying {
                ch.service.peripheral.setNotifyValue(false, forCharacteristic: ch)
            }
            if  let ch = serialCharacteristic where ch.properties.contains(.Notify) {
                ch.service.peripheral.setNotifyValue(true, forCharacteristic: ch)
            }
        }
    }

    
    // MARK: -
    
    private  let receiveBuffer         = NSMutableData()
    
    
    // MARK: -
    
    private  var onConnectCallback:    ((success: Bool, error: NSError?) -> Void)?
    
    
    // MARK: -
    
    /// That delegate object that should receive peripheral events.
    public weak var delegate:            BLESerialPeripheralDelegate?
    
    
    // MARK: - Accessors
    
    /// The unique identifier associated with the peripheral.
    ///
    /// - seealso: `CBPeripheral.identifier` for more information.
    public   var identifier:             NSUUID {
        return cbPeripheral.identifier
    }
    
    /// The human-readable name of the peripheral.
    public   var name:                   String? {
        return cbPeripheral.name
    }
    
    /// The current connection state of the peripheral.
    public   var state:                  CBPeripheralState {
        return cbPeripheral.state
    }
    
    
    // MARK: -
    
    /// The local name of the device if any.
    public  var localName:          String? {
        return advertisementData[CBAdvertisementDataLocalNameKey] as? String
    }
    
    
    // MARK: - Init
    
    init(serialManager: BLESerialManager, peripheral: CBPeripheral, advertisementData: [String: AnyObject]) {
        self.serialManager     = serialManager
        self.cbPeripheral      = peripheral
        self.advertisementData = advertisementData
        
        // Continue init
        super.init()
        
        // Attach self as delegate to the peripheral
        peripheral.delegate    = self
    }
}


// MARK: - Connection

extension BLESerialPeripheral {
    
    /// Establishes a local connection to the peripheral.
    ///
    /// As part of connecting, the wrapper also interrogates the device for it's
    /// services and characteristics.
    ///
    /// If a connection is succesfully established, the `serialPeripheralDidConnect:`
    /// method of the delegate is invoked. If the connection attempt fails, the
    /// `serialPeripheral:didFailToConnectWithError:` method of the delegate is
    /// invoked.
    ///
    /// - parameter completion: A handler to be invoked when the connection attempt
    ///   succeeds or fails.
    ///
    /// - seealso: `disconnect`
    public func connect(completion completion: ((success: Bool, error: NSError?) -> Void)?) {
        assertIsMainThread()
        onConnectCallback = completion
        serialManager.connectPeripheral(self)
    }
    
    /// Disconnects or cancels an active or pending connection to the peripheral.
    ///
    /// On disconnect, the `serialPeripheral:didDisconnectWithError:` method of
    /// the delegate is invoked.
    public func disconnect() {
        assertIsMainThread()
        
        // Cleanup callbacks
        onConnectCallback = nil
        
        // Disconnect
        serialManager.disconnectPeripheral(self)
    }
}


// MARK: - Reading Data

extension BLESerialPeripheral {
    
    /// Returns `true` if there is data available in the receive buffer.
    public  var hasBytesAvailable:    Bool {
        assertIsMainThread()
        return receiveBuffer.length > 0
    }
    
    /// Returns the length of data available in the receive buffer.
    public  var bytesAvailableLength: Int {
        assertIsMainThread()
        return receiveBuffer.length
    }
    
    
    // MARK: -
    
    /// Reads (and removes) a single byte if data (if available) from the
    /// receive buffer.
    ///
    /// - returns: A single byte if available.
    public func readByte() -> Int8? {

        // Read a byte of data
        guard let data = read(maxLength: 1, parse: { $0.data }) else {
            return nil
        }
        
        // Extract byte
        var byte: Int8 = 0
        data.getBytes(&byte, length: 1)
        
        // Return byte
        return byte
    }
    
    /// Reads (and removes) data from the receive buffer if available.
    ///
    /// - parameter maxLength: An optional maximum number of bytes to read.
    ///
    /// - returns: an `NSData` object with the data extracted from the receive 
    ///   buffer if available.
    public func readData(maxLength maxLength: Int? = nil) -> NSData? {
        return read(maxLength: maxLength) { $0.data }
    }
    
    /// Reads (and removes) data as a `String` from the receive buffer if 
    /// available using the given encoding.
    ///
    /// NOTE: If the data could not be converted to unicode using the given
    /// encoding, it is not removed from the buffer.
    ///
    /// - parameter encoding:  The string encoding of the data. The default is `NSUTF8StringEncoding`.
    /// - parameter maxLength: An optional maximum number of bytes to read. Exercise
    ///   caution as some characters may be multi-byte.
    ///
    /// - returns: a `String` object with the data extracted using the given encoding
    ///   if the buffer is not empty and if conversion was succesfull.
    public func readString(encoding encoding: NSStringEncoding = NSUTF8StringEncoding, maxLength: Int? = nil) -> String? {
        return read(maxLength: maxLength) { data, remove in
            
            // Convert data to string
            let string = String(data: data, encoding: encoding)
            
            // Remove if conversion succesfull
            remove = string != nil
            
            // Return converted string
            return string
        }
    }
    
    
    // MARK: -
    
    private func read<T>(maxLength maxLength: Int?, parse: (data: NSData, inout remove: Bool) -> T?) -> T? {
        assertIsMainThread()

        // Abort if buffer is empty
        if  receiveBuffer.length == 0 {
            return nil
        }
        
        // Read data
        let length = min(receiveBuffer.length, maxLength ?? Int.max)
        let range  = NSRange(location: 0, length: length)
        let data   = receiveBuffer.subdataWithRange(range)

        // Parse it using the callback
        var remove = true
        let parsed = parse(data: data, remove: &remove)
        
        // Delete data that was read if required
        if  remove {
            receiveBuffer.replaceBytesInRange(range, withBytes: nil, length: 0)
        }
        
        // Return parsed data
        return parsed
    }
}


// MARK: - Events

extension BLESerialPeripheral {
    
    func onDidConnect() {
        
        // Discover the device's services
        cbPeripheral.discoverServices(nil)
    }
    
    func onDidDisconnect(error error: NSError?) {
        
        // Cleanup state
        serialCharacteristic = nil
        
        // Cleanup callbacks
        onConnectCallback = nil
        
        // Notify delegate
        delegate?.serialPeripheral?(self, didDisconnectWithError: error)
    }
    
    func onDidFailToConnect(error error: NSError?) {
        
        // Invoke connection callback
        onConnectCallback?(success: false, error: error)
        onConnectCallback = nil
        
        // Notify delegate
        delegate?.serialPeripheral?(self, didFailToConnectWithError: error)
    }
    
    
    // MARK: -
    
    func onDidDiscoverServicesAndCharacteristics() {
        
        // Invoke connection callback if any
        onConnectCallback?(success: true, error: nil)
        onConnectCallback = nil
        
        // Notify delegate
        delegate?.serialPeripheralDidConnect?(self)
    }
}


// MARK: - Peripheral Delegate

extension BLESerialPeripheral: CBPeripheralDelegate {
    
    public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        
        // Log error if any
        if  let errorU = error {
            DDLogError("\(CurrentFileName()): Error discovering services - \(errorU)")
        }
        
        // Discover characteristcs for all services
        if  let services = peripheral.services where services.count > 0 {
            DDLogVerbose("\(CurrentFileName()): Discovered services for peripheral - \(cbPeripheral)")
            DDLogVerbose("\t Services: \(services)")
            
            for service in services {
                peripheral.discoverCharacteristics(nil, forService: service)
            }
        }
        
        // Finish discovery if there are no services
        else {
            onDidDiscoverServicesAndCharacteristics()
        }
    }
    
    public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        
        // Log error if any
        if  let errorU = error {
            DDLogError("\(CurrentFileName()): Error discovering characteristics for service [\(service)] - \(errorU)")
        }
        
        
        // Log characteristics & locate the serial characteristic
        if  let characteristics = service.characteristics where characteristics.count > 0 {
            DDLogVerbose("\(CurrentFileName()): Discovered characteristics for service - \(service.UUID)")
            DDLogVerbose("\t Characteristics - \(characteristics)")
            
            // Usually the serial service has only 1 characteristic. That will
            // be the one on which we transmit & receive
            if  service.UUID == serialManager.serialServiceUUID {
                serialCharacteristic = characteristics[0]
            }
        }
        
        
        // Finish discovery when all characteristics for all services have been discovered
        if  cbPeripheral.services!.filter({ $0.characteristics == nil }).count == 0 {
            onDidDiscoverServicesAndCharacteristics()
        }
    }
    
    
    // MARK: -
    
    public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        
        // Log error if any & abort
        if  let errorU = error {
            DDLogError("\(CurrentFileName()): Error reading value for serial characteristic of peripheral \(cbPeripheral) - \(errorU)")
            return
        }
        
        // Extract data and append it to the buffer. Then notify the delegate
        if  let data = characteristic.value {
            receiveBuffer.appendData(data)
            
            // Log event
            DDLogVerbose("\(CurrentFileName()): Received \(data.length) bytes of data")
            
            // Notify delegate
            delegate?.serialPeripheral?(self, didReceiveBytes: data.length)
        }
    }
    

    // MARK: -
    
    public func peripheralDidUpdateName(peripheral: CBPeripheral) {
        
        // Log event
        let name = peripheral.name
        DDLogVerbose("\(CurrentFileName()): Peripheral \(peripheral) update its name - \(name ?? "<nil>")")
        
        // Notify delegate
        delegate?.serialPeripheral?(self, didUpdateName: name)
    }
}