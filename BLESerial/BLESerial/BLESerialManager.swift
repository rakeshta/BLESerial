//
//  BLESerialManager.swift
//  BLE Smart Car Remote
//
//  Created by Rakesh TA on 20/02/2016.
//  Copyright © 2016 Raptor Soft. All rights reserved.
//

import Foundation
import CoreBluetooth
import CocoaLumberjackSwift


// MARK: - CBCentralManagerState

extension CBCentralManagerState: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .Unknown:      return "Unknown"
        case .Resetting:    return "Resetting"
        case .Unsupported:  return "Unsupported"
        case .Unauthorized: return "Unauthorized"
        case .PoweredOff:   return "PoweredOff"
        case .PoweredOn:    return "PoweredOn"
        }
    }
}


// MARK: - WeakReference

private class WeakReference<T: AnyObject> {
    private weak var instance: T?
    private init(_ instance: T) {
        self.instance = instance
    }
}


// MARK: - BLESerialManagerScanDelegate

public protocol BLESerialManagerScanDelegate: AnyObject {
    func serialManager(serialManager: BLESerialManager, didDiscoverPeripheral peripheral: BLESerialPeripheral)
}


// MARK: - BLESerialManager

public final class BLESerialManager: NSObject {
    
    // MARK: - Members
    
    public  var serialServiceUUID             =  CBUUID(string: "FFE0")
    public  var serialCharacteristicUUID      =  CBUUID(string: "FFE1")
    
    public  weak var scanDelegate:               BLESerialManagerScanDelegate?
    
    
    // MARK: -
    
    private var centralManager:                  CBCentralManager!
    
    private var scanTimeoutTimer:                NSTimer?
    
    private var serialPeripherals             = [WeakReference<BLESerialPeripheral>]()
    
    
    // MARK: - Accessors
    
    public  var state:                           CBCentralManagerState {
        return centralManager.state
    }
    
    public  var isScanning:                      Bool {
        return centralManager.isScanning
    }
    
    
    // MARK: - Init
    
    public init(restoreIdentifier: String?) {
        super.init()
        
        // Create central manager
        var options    = [CBCentralManagerOptionShowPowerAlertKey: true] as [String: AnyObject]
        if  let identU = restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = identU
        }
        
        centralManager = CBCentralManager(
            delegate: self,
            queue:    nil,
            options:  options
        )
    }
}


// MARK: - Managing Peripheral Instances

extension BLESerialManager {
    
    private func createSerialPeripheral(cbPeripheral cbPeripheral: CBPeripheral, advertisementData: [String : AnyObject]) -> BLESerialPeripheral {
        let peripheral = BLESerialPeripheral(serialManager: self, peripheral: cbPeripheral, advertisementData: advertisementData)
        serialPeripherals.append(WeakReference(peripheral))
        return peripheral
    }
    
    private func findSerialPeripheral(cbPeripheral cbPeripheral: CBPeripheral) -> BLESerialPeripheral? {
        assert(NSThread.isMainThread(), "FATAL: Should be invoked on main thread")

        guard let index = serialPeripherals.indexOf({ $0.instance?.cbPeripheral === cbPeripheral }) else {
            return nil
        }

        return serialPeripherals[index].instance
    }
    
    private func cleanupSerialPeripherals() {
        assert(NSThread.isMainThread(), "FATAL: Should be invoked on main thread")
        serialPeripherals = serialPeripherals.filter { $0.instance != nil }
    }
    
    private func delayedCleanupSerialPeripherals() {
        let popTime = dispatch_time(DISPATCH_TIME_NOW, Int64((1.0 * Double(NSEC_PER_SEC))));
        dispatch_after(popTime, dispatch_get_main_queue()) {
            self.cleanupSerialPeripherals()
        }
    }
}


// MARK: - Scanning

extension BLESerialManager {
    
    public func startScan(timeout timeout: NSTimeInterval? = nil) {
        assert(NSThread.isMainThread(), "FATAL: Should be invoked on main thread")
        
        // Abort if already scanning
        if  isScanning {
            return
        }
        
        // Start scan
        DDLogInfo("\(CurrentFileName()): Starting scan for peripherals")
        
        centralManager.scanForPeripheralsWithServices([serialServiceUUID], options: nil)
        
        // Create a timer to time-out the scan if required
        if  let timeoutU = timeout {
            scanTimeoutTimer = NSTimer.scheduledTimerWithTimeInterval(timeoutU, target: self, selector: "scanTimeoutTimerFired:", userInfo: nil, repeats: false)
        }
    }
    
    public func stopScan() {
        assert(NSThread.isMainThread(), "FATAL: Should be invoked on main thread")

        // Abort if not scanning
        if  isScanning == false {
            return
        }
        
        // Stop scan
        DDLogInfo("\(CurrentFileName()): Stopping scan for peripherals")
        
        centralManager.stopScan()
        
        // Invalidate timeout timer
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        
        // Cleanup our list of peripherals after a moment
        delayedCleanupSerialPeripherals()
    }
    
    
    // MARK: -
    
    func scanTimeoutTimerFired(timer: NSTimer) {
        DDLogVerbose("\(CurrentFileName()): Scan timeout occurred")
        stopScan()
    }
}


// MARK: - Connection Management

extension BLESerialManager {
    
    func connectPeripheral(peripheral: BLESerialPeripheral) {
        
        // Disconnect peripheral if needed
        disconnectPeripheral(peripheral)
        
        // (Re)connect peripheral
        DDLogInfo("\(CurrentFileName()): Connecting peripheral - \(peripheral.cbPeripheral)")
        
        centralManager.connectPeripheral(peripheral.cbPeripheral, options: nil)
    }
    
    func disconnectPeripheral(peripheral: BLESerialPeripheral) {
        
        // Abort if not connected
        if  peripheral.state == .Connecting || peripheral.state == .Connected {
            return
        }
        
        // Disconnect peripheral
        DDLogInfo("\(CurrentFileName()): Disconnecting peripheral - \(peripheral.cbPeripheral)")

        centralManager.cancelPeripheralConnection(peripheral.cbPeripheral)
        
        // Cleanup peripherals after a bit
        delayedCleanupSerialPeripherals()
    }
}


// MARK: - Central Manager Delegae

extension BLESerialManager: CBCentralManagerDelegate {
    
    public func centralManagerDidUpdateState(central: CBCentralManager) {
        DDLogVerbose("\(CurrentFileName()): Central manager did update state - \(central.state)")
    }
    
    public func centralManager(central: CBCentralManager, willRestoreState dict: [String : AnyObject]) {
        DDLogVerbose("\(CurrentFileName()): Central manager will restore state - \(central.state)")
    }
    
    
    // MARK: -
    
    public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        DDLogVerbose("\(CurrentFileName()): Discovered peripheral - \(peripheral)")
        DDLogVerbose("\t Advertisement data: \(advertisementData)")
        DDLogVerbose("\t RSSI: \(RSSI)")
        
        let serialPeripheral = createSerialPeripheral(cbPeripheral: peripheral, advertisementData: advertisementData)
        scanDelegate?.serialManager(self, didDiscoverPeripheral: serialPeripheral)
        
        // Opportunity to cleanup
        cleanupSerialPeripherals()
    }
    
    
    // MARK: -
    
    public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        DDLogInfo("\(CurrentFileName()): Connected peripheral - \(peripheral)")

        // Notify peripheral of event
        let serialPeripheral = findSerialPeripheral(cbPeripheral: peripheral)!
        serialPeripheral.onDidConnect()
    }
    
    public func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        if  let errorU = error {
            DDLogError("\(CurrentFileName()): Disconnected peripheral - \(peripheral)")
            DDLogError("\t Error - \(errorU)")
        }
        else {
            DDLogInfo("\(CurrentFileName()): Disconnected peripheral - \(peripheral)")
        }
        
        // Notify peripheral of event
        let serialPeripheral = findSerialPeripheral(cbPeripheral: peripheral)
        serialPeripheral?.onDidDisconnect(error: error)
        
        // Opportunity to cleanup
        cleanupSerialPeripherals()
    }
    
    public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        DDLogError("\(CurrentFileName()): Failed to connect peripheral - \(peripheral)")
        if  let errorU = error {
            DDLogError("\t Error - \(errorU)")
        }

        // Notify peripheral of event
        let serialPeripheral = findSerialPeripheral(cbPeripheral: peripheral)
        serialPeripheral?.onDidFailToConnect(error: error)
    }
}
