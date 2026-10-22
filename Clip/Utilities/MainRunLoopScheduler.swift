import Foundation

enum MainRunLoopScheduler {
    static func perform(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            work()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    static func performInDefaultMode(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            work()
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
