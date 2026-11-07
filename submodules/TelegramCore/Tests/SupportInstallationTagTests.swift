import Foundation
import XCTest
import Postbox
import SwiftSignalKit
@testable import TelegramCore

final class SupportInstallationTagTests: XCTestCase {
    private var postbox: Postbox!
    private var directory: URL!

    override func setUpWithError() throws {
        initializeAccountManagement()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("support-tag-tests-" + UUID().uuidString)
        let encryption = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: try XCTUnwrap(.init(data: Data(count: 32))), salt: try XCTUnwrap(.init(data: Data(count: 16))))
        let opened = try value(openPostbox(basePath: directory.path, seedConfiguration: telegramPostboxSeedConfiguration, encryptionParameters: encryption, timestampForAbsoluteTimeBasedOperations: Int32(Date().timeIntervalSince1970), isMainProcess: true, isTemporary: false, isReadOnly: false, useCopy: false, useCaches: true, removeDatabaseOnError: false)
            |> filter { result in
                if case .upgrading = result { return false }
                return true
            })
        guard case let .postbox(postbox) = opened else {
            throw NSError(domain: "SupportInstallationTagTests", code: 1)
        }
        self.postbox = postbox
    }

    override func tearDownWithError() throws {
        if let postbox = postbox {
            let _ = try value(postbox.transaction { _ in })
            let _ = try value(postbox.mediaBox.storageBox.all())
            let _ = try value(postbox.mediaBox.cacheStorageBox.all())
            postbox.mediaBox.dataQueue.sync {}
        }
        postbox = nil
        Postbox.sharedQueue.sync {}
        if let directory = directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func value<T>(_ signal: Signal<T, NoError>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        let completed = expectation(description: "signal completed")
        let result = Atomic<T?>(value: nil)
        let disposable = (signal |> take(1)).start(next: { value in
            let _ = result.swap(value)
        }, completed: { completed.fulfill() })
        defer { disposable.dispose() }
        wait(for: [completed], timeout: 15)
        return try XCTUnwrap(result.with { $0 }, file: file, line: line)
    }

    func testTagIsCreatedOnceAndKept() throws {
        let first = try value(postbox.transaction { transaction -> UInt64 in
            return supportInstallationTag(transaction: transaction)
        })
        let second = try value(postbox.transaction { transaction -> UInt64 in
            return supportInstallationTag(transaction: transaction)
        })
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first & 0xffffffff, 0)
    }

    private func legacyKey(_ value: Int32) -> ValueBoxKey {
        let key = ValueBoxKey(length: 4)
        key.setInt32(0, value: value)
        return key
    }

    func testLegacyEntriesMoveToTheNewKeysOnce() throws {
        var settings = SupportSettings.default
        settings.swipeToNextChat = true
        let moved = try value(postbox.transaction { transaction -> (SupportSettings?, Int64?, Bool, Bool) in
            transaction.setPreferencesEntry(key: self.legacyKey(52), value: PreferencesEntry(settings))
            transaction.setPreferencesEntry(key: self.legacyKey(53), value: PreferencesEntry(SupportInstallationTag(value: 12345)))
            supportMoveLegacyPreferences(transaction: transaction)
            return (
                transaction.getPreferencesEntry(key: PreferencesKeys.supportSettings)?.get(SupportSettings.self),
                transaction.getPreferencesEntry(key: PreferencesKeys.supportInstallationTag)?.get(SupportInstallationTag.self)?.value,
                transaction.getPreferencesEntry(key: self.legacyKey(52)) == nil,
                transaction.getPreferencesEntry(key: self.legacyKey(53)) == nil
            )
        })
        XCTAssertEqual(moved.0?.swipeToNextChat, true)
        XCTAssertEqual(moved.1, 12345)
        XCTAssertTrue(moved.2)
        XCTAssertTrue(moved.3)
    }

    func testAnEntryAtTheOldKeyIsLeftAloneOnceTheSettingsAreMoved() throws {
        let kept = try value(postbox.transaction { transaction -> Bool in
            supportMoveLegacyPreferences(transaction: transaction)
            transaction.setPreferencesEntry(key: self.legacyKey(52), value: PreferencesEntry(SupportInstallationTag(value: 1)))
            supportMoveLegacyPreferences(transaction: transaction)
            return transaction.getPreferencesEntry(key: self.legacyKey(52)) != nil
        })
        XCTAssertTrue(kept)
        let settings = try value(postbox.transaction { transaction -> SupportSettings? in
            return transaction.getPreferencesEntry(key: PreferencesKeys.supportSettings)?.get(SupportSettings.self)
        })
        XCTAssertEqual(settings, SupportSettings.default)
    }

    func testFirstTagIsStored() throws {
        let tag = try value(postbox.transaction { transaction -> UInt64 in
            return supportInstallationTag(transaction: transaction)
        })
        let stored = try value(postbox.transaction { transaction -> SupportInstallationTag? in
            return transaction.getPreferencesEntry(key: PreferencesKeys.supportInstallationTag)?.get(SupportInstallationTag.self)
        })
        XCTAssertEqual(stored.map { UInt64(bitPattern: $0.value) }, tag)
    }
}
