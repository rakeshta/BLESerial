//
//  SwiftUtils.swift
//  BLESerial
//
//  Created by Rakesh TA on 22/02/2016.
//  Copyright © 2016 Raptor Soft. All rights reserved.
//

import Foundation


// MARK: - Misc

public func with<T>(some: T, @noescape block: T throws -> Void) rethrows -> T {
    try block(some)
    return some
}

public func assertIsMainThread(file: StaticString = __FILE__, line: UInt = __LINE__) {
    assert(NSThread.isMainThread(), "FATAL: Invalid thread access", file: file, line: line)
}


// MARK: - Dispatch

public enum Queue {
    case Main
    case HighPriority
    case DefaultPriority
    case LowPriority
    case Background
    
    private var dispatchQueue: dispatch_queue_t {
        switch self {
        case .Main:            return dispatch_get_main_queue()
        case .HighPriority:    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
        case .DefaultPriority: return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        case .LowPriority:     return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)
        case .Background:      return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
        }
    }
    
    public func async(block: () -> Void) {
        dispatch_async(dispatchQueue, block)
    }
    
    public func sync<T>(block: () -> T) -> T {
        
        // Execute immediate if already in main thread
        if  self == .Main && NSThread.isMainThread() {
            return block()
        }
        
        // Execute sync
        var ret: T? = nil
        dispatch_sync(dispatchQueue) {
            ret = block()
        }
        
        // Value will exist
        return ret!
    }
    
    public func after(delay: NSTimeInterval, block: () -> Void) {
        let popTime = dispatch_time(DISPATCH_TIME_NOW, Int64((delay * Double(NSEC_PER_SEC))));
        dispatch_after(popTime, dispatchQueue, block)
    }
}
