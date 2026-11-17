@testable import CurfewKit
import Darwin
import Foundation
import Testing

/// The process table can grow between the call that sizes it and the call
/// that reads it. When it outgrows the reader's slack the kernel answers
/// `ENOMEM`, and an empty list would tell both kill paths that no agent is
/// running, so the reader must read again.
struct SysctlProcessEnumeratorTests {
    /// A table that grows by `growth` entries between every sizing and read,
    /// for the first `growingReads` reads.
    private final class GrowingTable {
        var entries: [(pid: Int32, name: String)]
        let growth: Int
        var growingReads: Int
        private(set) var reads = 0

        init(entries: [(pid: Int32, name: String)], growth: Int, growingReads: Int) {
            self.entries = entries
            self.growth = growth
            self.growingReads = growingReads
        }

        func read(_ buffer: UnsafeMutableRawPointer?, _ length: inout Int) -> Int32 {
            let stride = MemoryLayout<kinfo_proc>.stride
            guard let buffer else {
                length = entries.count * stride
                return 0
            }
            reads += 1
            if growingReads > 0 {
                growingReads -= 1
                let next = Int32(entries.count + 1000)
                entries += (0 ..< growth).map { (next + Int32($0), "cc") }
            }
            guard entries.count * stride <= length else { return ENOMEM }
            let table = buffer.bindMemory(to: kinfo_proc.self, capacity: entries.count)
            for (index, entry) in entries.enumerated() {
                var record = kinfo_proc()
                record.kp_proc.p_pid = entry.pid
                withUnsafeMutableBytes(of: &record.kp_proc.p_comm) { bytes in
                    for (offset, byte) in entry.name.utf8.prefix(bytes.count - 1).enumerated() {
                        bytes[offset] = byte
                    }
                }
                table[index] = record
            }
            length = entries.count * stride
            return 0
        }
    }

    @Test("A table that outgrows the slack is read again rather than reported empty")
    func outgrownTableIsReadAgain() {
        let table = GrowingTable(
            entries: [(1, "launchd"), (4242, "claude")], growth: 40, growingReads: .max
        )
        let enumerator = SysctlProcessEnumerator(readTable: table.read)

        let processes = enumerator.runningProcesses()

        // 16 and 32 entries of slack are outgrown; 64 is not.
        #expect(table.reads == 3)
        #expect(processes.contains {
            $0.processIdentifier == 4242 && $0.executableName == "claude"
        })
        #expect(processes.count == table.entries.count)
    }

    @Test("A table that never stops outgrowing the reader gives up after bounded attempts")
    func endlessGrowthIsBounded() {
        let table = GrowingTable(
            entries: [(4242, "claude")], growth: 5000, growingReads: .max
        )
        let enumerator = SysctlProcessEnumerator(readTable: table.read)

        #expect(enumerator.runningProcesses().isEmpty)
        #expect(table.reads == SysctlProcessEnumerator.readAttempts)
    }

    @Test("The kernel reader sees this test's own process")
    func kernelReaderSeesThisProcess() {
        let processes = SysctlProcessEnumerator().runningProcesses()
        #expect(processes.contains { $0.processIdentifier == getpid() })
    }
}
