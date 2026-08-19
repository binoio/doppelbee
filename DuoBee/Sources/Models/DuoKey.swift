//
//  DuoKey.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation

struct DuoKey: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let secret: String
    let host: String
    var counter: Int
    let publicKey: String?
    let privateKey: String?
    let pkey: String?
    let akey: String?
    var autoConfirmPush: Bool

    init(id: UUID = UUID(), name: String, secret: String, host: String, counter: Int = 0, publicKey: String? = nil, privateKey: String? = nil, pkey: String? = nil, akey: String? = nil, autoConfirmPush: Bool = false) {
        self.id = id
        self.name = name
        self.secret = secret
        self.host = host
        self.counter = counter
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.pkey = pkey
        self.akey = akey
        self.autoConfirmPush = autoConfirmPush
    }

    mutating func incrementCounter() {
        counter += 1
    }
}
