//
//  DuoDatabaseTests.swift
//  DuoBeeTests
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import DuoBee

final class DuoDatabaseTests: XCTestCase {
    func testDatabaseInitialization() {
        let database = DuoDatabase()

        XCTAssertTrue(database.keys.isEmpty)
    }

    func testAddKey() {
        var database = DuoDatabase()
        let key = DuoKey(name: "Test Key", secret: "TESTSECRET", host: "api-test.duosecurity.com")

        database.addKey(key)

        XCTAssertEqual(database.keys.count, 1)
        XCTAssertEqual(database.keys.first?.id, key.id)
        XCTAssertEqual(database.keys.first?.name, "Test Key")
    }

    func testRemoveKey() {
        var database = DuoDatabase()
        let key1 = DuoKey(name: "Key 1", secret: "SECRET1", host: "api-test1.duosecurity.com")
        let key2 = DuoKey(name: "Key 2", secret: "SECRET2", host: "api-test2.duosecurity.com")

        database.addKey(key1)
        database.addKey(key2)
        XCTAssertEqual(database.keys.count, 2)

        database.removeKey(withId: key1.id)
        XCTAssertEqual(database.keys.count, 1)
        XCTAssertEqual(database.keys.first?.id, key2.id)
    }

    func testUpdateKey() {
        var database = DuoDatabase()
        let key = DuoKey(name: "Original Name", secret: "SECRET", host: "api-test.duosecurity.com")

        database.addKey(key)

        var updatedKey = key
        updatedKey.name = "Updated Name"
        updatedKey.incrementCounter()

        database.updateKey(updatedKey)

        XCTAssertEqual(database.keys.count, 1)
        XCTAssertEqual(database.keys.first?.name, "Updated Name")
        XCTAssertEqual(database.keys.first?.counter, 1)
    }

    func testUpdateNonExistentKey() {
        var database = DuoDatabase()
        let key1 = DuoKey(name: "Key 1", secret: "SECRET1", host: "api-test.duosecurity.com")
        let key2 = DuoKey(name: "Key 2", secret: "SECRET2", host: "api-test.duosecurity.com")

        database.addKey(key1)

        // Try to update a key that doesn't exist in the database
        database.updateKey(key2)

        // Database should still only have key1
        XCTAssertEqual(database.keys.count, 1)
        XCTAssertEqual(database.keys.first?.id, key1.id)
    }

    func testDatabaseEncoding() throws {
        var database = DuoDatabase()
        let key = DuoKey(name: "Test Key", secret: "TESTSECRET", host: "api-test.duosecurity.com")
        database.addKey(key)

        let encoder = JSONEncoder()
        let data = try encoder.encode(database)

        XCTAssertGreaterThan(data.count, 0)
    }

    func testDatabaseDecoding() throws {
        var database = DuoDatabase()
        let key = DuoKey(name: "Test Key", secret: "TESTSECRET", host: "api-test.duosecurity.com")
        database.addKey(key)

        let encoder = JSONEncoder()
        let data = try encoder.encode(database)

        let decoder = JSONDecoder()
        let decodedDatabase = try decoder.decode(DuoDatabase.self, from: data)

        XCTAssertEqual(decodedDatabase.keys.count, database.keys.count)
        XCTAssertEqual(decodedDatabase.keys.first?.name, key.name)
        XCTAssertEqual(decodedDatabase.keys.first?.id, key.id)
    }
}
