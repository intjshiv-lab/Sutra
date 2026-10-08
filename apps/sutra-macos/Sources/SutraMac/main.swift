import AppKit
import Darwin

// ==============================================================================
// STRICT SINGLE-INSTANCE & ZERO-ZOMBIE ENFORCEMENT (POSIX flock on sutra.lock)
// ==============================================================================
let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
let sutraDir = (homeDir as NSString).appendingPathComponent(".sutra")
try? FileManager.default.createDirectory(atPath: sutraDir, withIntermediateDirectories: true)
let lockPath = (sutraDir as NSString).appendingPathComponent("sutra.lock")

let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o600)
if lockFd < 0 {
    exit(1)
}

// Attempt non-blocking exclusive lock
if flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
    // Another instance is already holding the lock!
    // Read the PID inside the lock file
    var buf = [CChar](repeating: 0, count: 32)
    let bytesRead = read(lockFd, &buf, 31)
    if bytesRead > 0 {
        let existingPidStr = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingPid = pid_t(existingPidStr), existingPid > 0 {
            // Check if process is still alive
            if kill(existingPid, 0) == 0 {
                // The primary instance is healthy and running. Gracefully exit immediately.
                exit(0)
            }
        }
    }

    // If existing PID was dead/zombie, wait briefly to acquire lock or force takeover
    if flock(lockFd, LOCK_EX) != 0 {
        exit(0)
    }
}

// Write our current PID to the lock file
ftruncate(lockFd, 0)
lseek(lockFd, 0, SEEK_SET)
let myPidStr = "\(getpid())\n"
_ = myPidStr.withCString { ptr in
    write(lockFd, ptr, strlen(ptr))
}
// Keep lockFd open for the entire process lifetime; macOS will release lock on exit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

