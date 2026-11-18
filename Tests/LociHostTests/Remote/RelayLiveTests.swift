import Foundation
import LociModel
import LociRemote
import LociStore
import Testing

@testable import LociHost

/// Against a real relay, skipped unless `LOCI_RELAY_URL` and `LOCI_RELAY_KEY` are set. It registers two
/// throwaway Macs, pairs them, runs a command and a subscription, and prints the round trip.
@Suite(.enabled(if: LiveRelay.relay != nil), .timeLimit(.minutes(2)))
struct RelayLiveTests {
  static func mac(_ name: String, model: MachineModel, relay: Relay) async throws -> TwoMacs.OneMac {
    let place = Place()
    let local = try await LocalHost.start(
      root: place.root, database: place.database, environment: TestWorld().environment)
    let key = try DeviceKey()
    let folder = MachineFolder(root: place.root.appending(path: ".machines"))
    let awake = RecordedSleep()
    let service = MachinesService(
      this: Machine(id: key.machineID, name: name, model: model), key: key, local: local,
      access: RelayAccess(relay: relay, dialer: NetworkDialer()), folder: folder, discovery: FakeLocalNetwork(),
      sleepGuard: awake, now: { Timestamp(.now) }, newID: { EntityID() })
    await service.start()
    return TwoMacs.OneMac(service: service, local: local, place: place, machineFolder: folder, key: key, awake: awake)
  }

  @Test func twoMacsPairAndWorkThroughTheRelay() async throws {
    let relay = try #require(LiveRelay.relay)
    let studio = try await Self.mac("Live Studio", model: .studio, relay: relay)
    let laptop = try await Self.mac("Live Laptop", model: .laptop, relay: relay)
    defer {
      Task {
        for mac in [studio, laptop] {
          await mac.service.stop()
          await mac.local.close()
          mac.place.remove()
        }
      }
    }

    let invite = try await studio.service.invite()
    var paired: Machine?
    for _ in 0..<20 where paired == nil {
      paired = try? await laptop.service.accept(invite)
      if paired == nil { try await Task.sleep(for: .milliseconds(500)) }
    }
    #expect(paired == studio.machine)

    let remote = laptop.service.open(studio.machine.id)
    var times: [Duration] = []
    for _ in 0..<7 {
      let started = ContinuousClock.now
      _ = try await remote.run(ListMentors())
      times.append(ContinuousClock.now - started)
    }
    let mentors = remote.subscribe(AllMentors())
    #expect(await value(mentors, within: .seconds(20)) { $0.isEmpty } != nil)
    _ = try await studio.local.run(CreateMentor(request: "Scheduling"))
    #expect(await value(mentors, within: .seconds(20)) { $0.count == 1 } != nil)

    let sorted = times.sorted()
    print("relay round trip: median \(sorted[sorted.count / 2]), fastest \(sorted[0]), slowest \(sorted.last ?? .zero)")
  }

  @Test func aSecondRegistrationOfTheSameTokenStopsTheFirst() async throws {
    let relay = try #require(LiveRelay.relay)
    let token = try DeviceKey().routeToken
    var first = RelayAgent(relay: relay, token: token, dialer: NetworkDialer()).run().makeAsyncIterator()
    guard case .registered(let proto) = await first.next() else { throw Unexpected() }
    print("relay protocol: \(proto)")
    let second = RelayAgent(relay: relay, token: token, dialer: NetworkDialer()).run()
    var secondEvents = second.makeAsyncIterator()
    guard case .registered = await secondEvents.next() else { throw Unexpected() }

    guard case .stopped(let reason) = await first.next() else { throw Unexpected() }

    #expect(reason == .displaced)
  }
}

enum LiveRelay {
  static var relay: Relay? {
    let environment = ProcessInfo.processInfo.environment
    guard let address = environment["LOCI_RELAY_URL"].flatMap(URL.init(string:)),
      let key = environment["LOCI_RELAY_KEY"], !key.isEmpty
    else { return nil }
    return Relay(address: address, registrationKey: key)
  }
}
