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
    
    /// That delegate object that should receive peripheral events.
    public weak var delegate:            BLESerialPeripheralDelegate?

    
    // MARK: -
    
    private  let serialManager:          BLESerialManager
    
    internal let cbPeripheral:           CBPeripheral
    
    private  let advertisementData:     [String: AnyObject]
    
    private  var serialCharacteristic:   CBCharacteristic?
    
    
    // MARK: -
    
    private  var onConnectCallback:    ((success: Bool, error: NSError?) -> Void)?
    
    
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
        onConnectCallback = completion
        serialManager.connectPeripheral(self)
    }
    
    /// Disconnects or cancels an active or pending connection to the peripheral.
    ///
    /// On disconnect, the `serialPeripheral:didDisconnectWithError:` method of
    /// the delegate is invoked.
    public func disconnect() {
        
        // Cleanup callbacks
        onConnectCallback = nil
        
        // Disconnect
        serialManager.disconnectPeripheral(self)
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
    
    public func peripheralDidUpdateName(peripheral: CBPeripheral) {
        
        // Log event
        let name = peripheral.name
        DDLogVerbose("\(CurrentFileName()): Peripheral \(peripheral) update its name - \(name ?? "<nil>")")
        
        // Notify delegate
        delegate?.serialPeripheral?(self, didUpdateName: name)
    }
}