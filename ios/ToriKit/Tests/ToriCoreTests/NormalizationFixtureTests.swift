import Testing
import ToriCore
import ToriTestSupport

let textKeyFiles = ["match-key", "translation-key", "sentence-key", "tag-key", "search-fold", "url-key"]

@Test(arguments: textKeyFiles.flatMap { Fixture.cases("normalization/\($0).json") })
func textKey(_ c: FixtureCase) {
    let fn: (String) -> String = switch c.file["function"].string! {
    case "matchKey": TextKey.matchKey
    case "translationKey": TextKey.translationKey
    case "sentenceKey": TextKey.sentenceKey
    case "tagKey": TextKey.tagKey
    case "searchFold": TextKey.searchFold
    case "urlKey": TextKey.urlKey
    default: fatalError("unknown function")
    }
    let actual = fn(c["input"].string!)
    #expect(sameScalars(actual, c["expected"].string), "\(actual.debugDescription)")
}

@Test(arguments: Fixture.cases("normalization/source-key.json"))
func sourceKey(_ c: FixtureCase) {
    let i = c["input"], e = c["expected"]
    let key = SourceKey(title: i["title"].string, app: i["app"].string, isSuggested: i["kind"].string == "suggested")
    #expect(sameScalars(key.title, e["title"].string))
    #expect(sameScalars(key.app, e["app"].string))
    #expect(key.suggested == e["suggested"].bool)
}

/// BINARY collation on UTF-8, checked in memory here (the SQL check comes with the store).
@Test(arguments: Fixture.cases("normalization/text-order.json"))
func textOrder(_ c: FixtureCase) {
    var keys = c["keys"].array.map { Array($0.string!.utf8) }.sorted { $0.lexicographicallyPrecedes($1) }
    if let p = c["prefix"].string {
        let lo = Array(p.utf8), hi = lo + [0xFF, 0xFF]
        keys = keys.filter { !$0.lexicographicallyPrecedes(lo) && $0.lexicographicallyPrecedes(hi) }
    }
    #expect(keys == c["expected"].array.map { Array($0.string!.utf8) })
}

@Test func isPhrase() {
    #expect(TextKey.isPhrase("give up"))
    #expect(TextKey.isPhrase("  give\u{00A0}up "))
    #expect(!TextKey.isPhrase(" run. "))
}
