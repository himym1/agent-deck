import XCTest
@testable import agent_deck

/// Regression coverage for the built-in agent `disabled` override read path.
///
/// `BuiltinOverrideRecord.values` stores `JSONValue` (an enum), so the previous
/// `values["disabled"] as? Bool` casts in the Project Assignment UI and the
/// resolver-mirroring helpers always evaluated to `nil`. Disabling a built-in
/// agent flipped `resolved.disabled` (strikethrough) but left the assignment
/// card stuck — "All Projects" snapped back on and the per-project rows became
/// unclickable. These tests pin the `boolValue` read so the cast can't return.
final class BuiltinOverrideDisabledTests: XCTestCase {
    /// `boolValue` is the only correct read of a `JSONValue.bool`. The old call
    /// sites used `as? Bool`, which the compiler flags as "always fails" — that
    /// cast silently yielded nil and is what broke the assignment UI.
    func testJSONValueBoolReadsThroughBoolValue() {
        XCTAssertEqual(JSONValue.bool(true).boolValue, true)
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertNil(JSONValue.string("true").boolValue)
    }

    func testDisabledOverrideReadsBoolValue() {
        XCTAssertEqual(makeOverride(values: ["disabled": .bool(true)]).disabledOverride, true)
        XCTAssertEqual(makeOverride(values: ["disabled": .bool(false)]).disabledOverride, false)
    }

    func testDisabledOverrideIsNilWhenKeyAbsent() {
        XCTAssertNil(makeOverride(values: [:]).disabledOverride)
        XCTAssertNil(makeOverride(values: ["model": .string("opus")]).disabledOverride)
    }

    /// A `disabled` key carrying a non-bool value (malformed settings) reads as
    /// "no opinion" rather than crashing or coercing.
    func testDisabledOverrideIsNilForNonBoolValue() {
        XCTAssertNil(makeOverride(values: ["disabled": .string("true")]).disabledOverride)
        XCTAssertNil(makeOverride(values: ["disabled": .number(1)]).disabledOverride)
    }

    private func makeOverride(values: [String: JSONValue]) -> BuiltinOverrideRecord {
        let path = "/tmp/.pi/agent/settings.json"
        return BuiltinOverrideRecord(
            agentName: "coder",
            scope: ScopeID(kind: .override, path: path),
            settingsPath: path,
            values: values
        )
    }
}
