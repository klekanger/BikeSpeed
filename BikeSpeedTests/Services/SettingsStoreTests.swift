import Foundation
import Testing

@testable import BikeSpeed

@Suite(.tags(.persistence))
struct SettingsStoreTests {

    @Test
    func settingsSurviveARelaunch() throws {
        try withThrowawayDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.maxGaugeSpeedKMH = 80
            store.measurementSystem = .imperial
            store.appLanguage = .norwegian
            store.autoPauseEnabled = false

            let relaunched = SettingsStore(defaults: defaults)

            #expect(relaunched.maxGaugeSpeedKMH == 80)
            #expect(relaunched.measurementSystem == .imperial)
            #expect(relaunched.appLanguage == .norwegian)
            #expect(relaunched.autoPauseEnabled == false)
        }
    }

    @Test
    func afreshInstallGetsTheDocumentedDefaults() throws {
        try withThrowawayDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            #expect(store.maxGaugeSpeedKMH == 60)
            #expect(store.measurementSystem == .metric)
            #expect(store.appLanguage == .system)
        }
    }

    /// `bool(forKey:)` reports an unset key as `false`, which is indistinguishable from the rider having
    /// deliberately switched auto-pause off — so the store reads it through `object(forKey:)` instead.
    /// Get this wrong and auto-pause silently ships disabled for every new install.
    @Test(.tags(.edgeCase))
    func autoPauseDefaultsToOnWhenNothingHasBeenSaved() throws {
        try withThrowawayDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            #expect(store.autoPauseEnabled)
        }
    }

    /// And an explicit "off" must still survive, rather than the default-on stamping over it.
    @Test(.tags(.edgeCase))
    func anExplicitlyDisabledAutoPauseIsNotOverriddenByTheDefault() throws {
        try withThrowawayDefaults { defaults in
            SettingsStore(defaults: defaults).autoPauseEnabled = false

            #expect(SettingsStore(defaults: defaults).autoPauseEnabled == false)
        }
    }

    // MARK: - Helpers

    /// A `UserDefaults` suite of its own per test, removed afterwards — otherwise these tests would read
    /// and write the developer's real settings, and each other's.
    private func withThrowawayDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "BikeSpeedTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
