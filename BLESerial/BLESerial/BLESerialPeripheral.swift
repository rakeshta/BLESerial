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

public protocol BLESerialPeripheralDelegate: AnyObject {
    func serialPeripheralDidConnect(serialPeripheral: BLESerialPeripheral)
    func serialPeripheral(serialPerihperal: BLESerialPeripheral, didDisconnectWithError error: NSError?)
    func serialPeripheral(serialPerihperal: BLESerialPeripheral, didFailToConnectWithError error: NSError?)
}


// MARK: - BLESerialPeripheral

public final class BLESerialPeripheral: NSObject {
    
    // MARK: - Members
    
    public weak var delegate:            BLESerialPeripheralDelegate?

    
    // MARK: -
    
    private  let serialManager:          BLESerialManager
    
    internal let cbPeripheral:           CBPeripheral
    
    private  let advertisementData:     [String: AnyObject]
    
    private  var serialCharacteristic:   CBCharacteristic?
    
    
    // MARK: -
    
    private  var onConnectCallback:    ((success: Bool, error: NSError?) -> Void)?
    
    
    // MARK: - Accessors
    
    public   var identifier:             NSUUID {
        return cbPeripheral.identifier
    }
    
    public   var name:                   String? {
        return cbPeripheral.name
    }
    
    public   var state:                  CBPeripheralState {
        return cbPeripheral.state
    }
    
    
    // MARK: -
    
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
    
    public func connect(completion completion: ((success: Bool, error: NSError?) -> Void)?) {
        onConnectCallback = completion
        serialManager.connectPeripheral(self)
    }
    
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
        delegate?.serialPeripheral(self, didDisconnectWithError: error)
    }
    
    func onDidFailToConnect(error error: NSError?) {
        
        // Invoke connection callback
        onConnectCallback?(success: false, error: error)
        onConnectCallback = nil
        
        // Notify delegate
        delegate?.serialPeripheral(self, didFailToConnectWithError: error)
    }
    
    
    // MARK: -
    
    func onDidDiscoverServices() {
        
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
        
        // Invoke connection callback if any if there are no services
        else {
            onConnectCallback?(success: true, error: nil)
            onConnectCallback = nil
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
        
        
        // Invoke connection callback when all characteristics for all services have been discovered
        if  cbPeripheral.services!.filter({ $0.characteristics == nil }).count == 0 {
            onConnectCallback?(success: true, error: nil)
            onConnectCallback = nil
        }
    }
}