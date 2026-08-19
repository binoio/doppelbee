//
//  DuoDatabase.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation

struct DuoDatabase: Codable {
    var keys: [DuoKey]

    init(keys: [DuoKey] = []) {
        self.keys = keys
    }

    mutating func addKey(_ key: DuoKey) {
        keys.append(key)
    }

    mutating func removeKey(withId id: UUID) {
        keys.removeAll { $0.id == id }
    }

    mutating func updateKey(_ key: DuoKey) {
        if let index = keys.firstIndex(where: { $0.id == key.id }) {
            keys[index] = key
        }
    }

    mutating func moveKeys(from source: IndexSet, to destination: Int) {
        keys.move(fromOffsets: source, toOffset: destination)
    }

    func getKey(withId id: UUID) -> DuoKey? {
        keys.first { $0.id == id }
    }
}
