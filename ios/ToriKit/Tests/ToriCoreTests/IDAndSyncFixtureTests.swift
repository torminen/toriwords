import Testing
import ToriCore
import ToriTestSupport

@Test(arguments: Fixture.cases("ids/uuid-v5.json"))
func uuidV5(_ c: FixtureCase) throws {
    #expect(ToriID.namespace.description == c.file["namespace"].string)
    let expected = c["uuid"].string
    #expect(ToriID.v5(c["name"].string!).description == expected)
    let p = c["params"]
    let id: ToriID? = switch c["record"].string! {
    case "languagePair": ToriID.languagePair(native: p["native"].string!, target: p["target"].string!)
    case "settings": ToriID.settings
    case "card": ToriID.card(entry: ToriID(p["entryId"].string!)!, direction: CardDirection(rawValue: p["direction"].string!)!)
    case "source": ToriID.source(urlKey: p["urlKey"].string!)
    case "entryTag": ToriID.entryTag(entry: ToriID(p["entryId"].string!)!, tag: ToriID(p["tagId"].string!)!)
    case "autoSense": ToriID.autoSense(entry: ToriID(p["entryId"].string!)!, ordinal: p["ordinal"].int!)
    default: nil  // importedReviewLog: a helper comes with Anki import (later)
    }
    if c["record"].string != "importedReviewLog" { #expect(id?.description == expected) }
}

@Test(arguments: Fixture.cases("ids/uuid-v7.json"))
func uuidV7(_ c: FixtureCase) {
    let id = ToriID.v7(unixMs: c["unixMs"].int64!, randA: UInt16(c["randA"].string!, radix: 16)!,
                       randB: UInt64(c["randB"].string!, radix: 16)!)
    #expect(id.description == c["uuid"].string)
    #expect(ToriID(c["uuid"].string!) == id)
}

@Test(arguments: Fixture.cases("ids/byte-order.json"))
func byteOrder(_ c: FixtureCase) {
    if c.json.has("a") {
        let a = ToriID(c["a"].string!)!, b = ToriID(c["b"].string!)!
        #expect((a < b ? -1 : a == b ? 0 : 1) == c["expected"].int)
        #expect(a.bytes.lexicographicallyPrecedes(b.bytes) == (a < b))
    } else {
        #expect(c["input"].array.map { ToriID($0.string!)! }.sorted().map(\.description) == c["expected"].array.map(\.string!))
    }
}

@Test func v7FromInjectedRandomness() {
    var rng = SplitMix(seed: 1)
    let id = ToriID.v7(unixMs: 1_762_790_400_000, using: &rng)
    #expect(id.description.hasPrefix("019a6e7e-e000-7"))
    #expect([0x8, 0x9, 0xa, 0xb].contains(id.bytes[8] >> 4))
}

struct SplitMix: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func hlcState(_ j: JSON) -> HLCState { HLCState(ms: j["ms"].int64!, counter: j["counter"].int!) }

@Test(arguments: Fixture.cases("hlc/local-write.json"))
func hlcLocalWrite(_ c: FixtureCase) {
    var s = hlcState(c["state"])
    let clock = s.localWrite(now: c["now"].int64!, node: UInt64(c.file["node"].string!, radix: 16)!)
    #expect(s == hlcState(c["expected"]["state"]))
    #expect(clock.description == c["expected"]["clock"].string)
    #expect(HLCTimestamp(clock.description) == clock)
}

@Test(arguments: Fixture.cases("hlc/receive.json"))
func hlcReceive(_ c: FixtureCase) {
    if c["type"].string == "serverSkew" {
        let ok = HLCState.serverAccepts(HLCTimestamp(c["clock"].string!)!, serverTime: c["serverTime"].int64!)
        #expect((ok ? "accepted" : "clock_skew") == c["expected"]["result"].string)
    } else {
        var s = hlcState(c["state"])
        s.receive(HLCTimestamp(c["remote"].string!)!, now: c["now"].int64!)
        #expect(s == hlcState(c["expected"]["state"]))
    }
}

@Test(arguments: Fixture.cases("hlc/clock-ahead.json"))
func hlcClockAhead(_ c: FixtureCase) {
    var s = hlcState(c["state"])
    let clocks = s.recoverIfAhead(lastServerTime: c["lastServerTime"].int64!, now: c["now"].int64!,
                                  node: UInt64(c.file["node"].string!, radix: 16)!, pendingFields: c["pendingFields"].int!)
    let e = c["expected"]
    #expect((clocks != nil) == e["reset"].bool)
    #expect(s == hlcState(e["state"]))
    #expect((clocks ?? []).map(\.description) == e["restampedClocks"].array.map(\.string!))
}

func field(_ j: JSON) -> FieldVersion<JSON> {
    FieldVersion(value: j["v"], clock: HLCTimestamp(j["c"].string!)!, rank: AuthorRank(rawValue: j["u"].int!)!)
}

func envelope(_ j: JSON) -> Envelope<JSON> {
    Envelope(id: ToriID(j["id"].string!)!, type: j["type"].string!, schema: j["schema"].int!,
             owner: j["owner"].string.flatMap(ToriID.init), deleted: j["deleted"].bool!,
             mergedInto: j["mergedInto"].string.flatMap(ToriID.init), fields: j["fields"].object.mapValues(field))
}

@Test(arguments: Fixture.cases("merge/field-comparator.json"))
func fieldComparator(_ c: FixtureCase) {
    let local = field(c["local"]), remote = field(c["remote"])
    #expect(FieldVersion.merge(local: local, remote: remote) == (c["expected"].string == "local" ? local : remote))
}

@Test(arguments: Fixture.cases("merge/envelope.json"))
func envelopeMerge(_ c: FixtureCase) {
    let local = envelope(c["local"]), remote = envelope(c["remote"]), expected = envelope(c["expected"])
    #expect(Envelope.merge(local: local, remote: remote) == expected)
    #expect(Envelope.merge(local: remote, remote: local) == expected)
    if c.json.has("remotePartial") {
        #expect(Envelope.merge(local: local, remote: envelope(c["remotePartial"])) == expected)
    }
}
