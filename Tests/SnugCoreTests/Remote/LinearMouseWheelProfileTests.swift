import Foundation
import SnugCore
import Testing

@Suite
struct LinearMouseWheelProfileTests {
    @Test
    func mergedMouseSettingsPreserveTheLocalDirectionAndDistance() throws {
        let profile = try parse(#"""
        {"schemes":[
          {"scrolling":{"reverse":{"vertical":false}}},
          {"if":{"device":{"category":"mouse"}},"scrolling":{"reverse":{"vertical":true}}},
          {"if":{"device":{"category":"mouse","vendorID":"0x1111","productID":"0x2222"}},
           "scrolling":{"distance":{"vertical":3}}},
          {"if":{"device":{"category":"mouse","vendorID":"0x1111","productID":"0x3333"}},
           "scrolling":{"speed":{"vertical":0}}},
          {"if":{"device":{"category":"trackpad"}},"scrolling":{"distance":{"vertical":30}}},
          {"if":{"app":"com.example.Editor","device":{"category":"mouse"}},
           "scrolling":{"distance":{"vertical":20}}}
        ]}
        """#)
        #expect(profile.verticalLines == 3)
        #expect(profile.direction(for: 1, macUsesNaturalScrolling: true) == 1)
        #expect(profile.direction(for: -1, macUsesNaturalScrolling: true) == -1)
        #expect(profile.direction(for: 1, macUsesNaturalScrolling: false) == -1)
    }

    @Test
    func multipleMouseProfilesFallBackToMouseCategory() throws {
        let profile = try parse(#"""
        {"schemes":[
          {"if":{"device":{"category":["mouse"]}},"scrolling":{"distance":{"vertical":4}}},
          {"if":{"device":{"category":"mouse","vendorID":"0x1111","productID":"0x2222"}},
           "scrolling":{"distance":{"vertical":3}}},
          {"if":{"device":{"category":"mouse","vendorID":"0x1111","productID":"0x3333"}},
           "scrolling":{"distance":{"vertical":5}}}
        ]}
        """#)
        #expect(profile.verticalLines == 4)
        #expect(profile.direction(for: 1, macUsesNaturalScrolling: true) == -1)
        #expect(profile.direction(for: -1, macUsesNaturalScrolling: false) == -1)
    }

    @Test
    func arrayConditionsAndLaterAutoDistanceOverrideEarlierLines() throws {
        let profile = try parse(#"""
        {"schemes":[
          {"scrolling":{"distance":{"vertical":3}}},
          {"if":[{"app":"com.example.Editor"},{"device":{"category":"mouse"}}],
           "scrolling":{"distance":{"vertical":"auto"}}}
        ]}
        """#)
        #expect(profile.verticalLines == nil)
    }

    @Test
    func rulesForTheSameModelMergeAcrossDifferentSpecificity() throws {
        let profile = try parse(#"""
        {"schemes":[
          {"if":{"device":{"category":"mouse","vendorID":"0x1111","productID":"0x2222"}},
           "scrolling":{"reverse":{"vertical":true}}},
          {"if":{"device":{"category":"mouse","vendorID":"0x1111","productID":"0x2222","productName":"Test mouse"}},
           "scrolling":{"distance":{"vertical":"3"}}}
        ]}
        """#)
        #expect(profile.reverseVertical)
        #expect(profile.verticalLines == 3)
    }

    @Test
    func malformedConfigurationIsRejected() {
        #expect(throws: (any Error).self) { try parse(#"{"schemes":["bad"]}"#) }
    }

    private func parse(_ string: String) throws -> LinearMouseWheelProfile {
        try LinearMouseWheelProfile(contents: Data(string.utf8))
    }
}
