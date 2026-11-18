import Foundation
import LociRemote
import LociStore
import Synchronization
import Testing

@testable import LociHost

struct DeviceKeyStorageTests {
  final class MemoryVault: KeyVault {
    let stored = Mutex<Data?>(nil)

    func load() throws(KeyVaultError) -> Data? { stored.withLock { $0 } }
    func save(_ key: Data) throws(KeyVaultError) { stored.withLock { $0 = key } }
  }

  @Test func aMacKeepsItsKeyAndSoItsIdentityAcrossLaunches() throws {
    let vault = MemoryVault()

    let first = try MachinesService.deviceKey(in: vault)
    let again = try MachinesService.deviceKey(in: vault)

    #expect(again.machineID == first.machineID)
    #expect(again.routeToken == first.routeToken)
  }

  @Test func theModelComesFromTheProductName() {
    #expect(ThisMac.model(fromProductName: "MacBook Pro (14-inch, M3, Nov 2023)") == .laptop)
    #expect(ThisMac.model(fromProductName: "Mac mini (2024)") == .mini)
    #expect(ThisMac.model(fromProductName: "Mac Studio (2025)") == .studio)
    #expect(ThisMac.model(fromProductName: "iMac (24-inch, 2024)") == .iMac)
    #expect(ThisMac.model(fromProductName: "") == .other)
  }
}
