import Foundation
import Testing
@testable import IndoorCoachKit

@Suite("Formatters")
struct FormattersTests {
    /// Charakterisierung: deutsches Komma, keine Tausenderpunkte, feste Nachkommastellen.
    @Test func decimalUsesGermanCommaWithoutGrouping() {
        #expect(Formatters.decimal(1.25, digits: 2) == "1,25")
        #expect(Formatters.decimal(1234.5, digits: 1) == "1234,5")
        #expect(Formatters.decimal(3, digits: 2) == "3,00")
        #expect(Formatters.decimal(142.6) == "143")
        #expect(Formatters.decimal(-0.04, digits: 1) == "-0,0")
        #expect(Formatters.decimal(12_345_678) == "12345678")
    }

    @Test func germanLocaleConstant() {
        #expect(Locale.de.identifier == "de_DE")
    }
}
