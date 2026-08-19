//
//  AddressBookLogicTests.swift
//  zodlTests
//
//  Batch 5 — address book. Covers AddressBook.State computed props (validation / error text /
//  context filtering / save-button gating) (Features/AddressBook/AddressBookStore.swift).
//

import Testing
import Foundation
import ComposableArchitecture
@testable import zodl_internal

@Suite(.serialized) struct AddressBookLogicTests {
    @Test func uniqueIdCombinesAddressAndChain() {
        var state = AddressBook.State()
        state.address = "addr"
        #expect(state.uniqueId == "addr-zcash")
        state.selectedChain = SwapAsset(provider: "", chain: "eth", token: "x", assetId: "", usdPrice: 0, decimals: 0)
        #expect(state.uniqueId == "addr-eth")
    }

    @Test func isNameOverMaxLength() {
        var state = AddressBook.State()
        state.name = "Alice"
        #expect(!state.isNameOverMaxLength)
        state.name = String(repeating: "a", count: 500)
        #expect(state.isNameOverMaxLength)
    }

    @Test func invalidNameErrorText() {
        var state = AddressBook.State()
        state.name = "Alice"
        #expect(state.invalidNameErrorText == nil)
        state.name = String(repeating: "a", count: 500)
        #expect(state.invalidNameErrorText == String(localizable: .addressBookErrorNameLength))
        state.name = "Alice"
        state.nameAlreadyExists = true
        #expect(state.invalidNameErrorText == String(localizable: .addressBookErrorNameExists))
    }

    @Test func addressBookContactsToShowFiltersByContext() {
        var state = AddressBook.State()
        let date = Date(timeIntervalSince1970: 0)
        state.$addressBookContacts.withLock {
            $0 = AddressBookContacts(lastUpdated: date, version: 2, contacts: [
                Contact(address: "zcashaddr", name: "Z", lastUpdated: date, chainId: nil),
                Contact(address: "ethaddr", name: "E", lastUpdated: date, chainId: "eth")
            ])
        }
        state.context = .swap
        #expect(state.addressBookContactsToShow.contacts.map(\.name) == ["E"]) // chainId != nil
        state.context = .send
        #expect(state.addressBookContactsToShow.contacts.map(\.name) == ["Z"]) // chainId == nil
        state.context = .settings
        #expect(state.addressBookContactsToShow.contacts.count == 2) // all
    }

    @Test func invalidAddressErrorTextAddressExists() {
        var state = AddressBook.State()
        state.addressAlreadyExists = true
        #expect(state.invalidAddressErrorText == String(localizable: .addressBookErrorAddressExists))
    }

    @Test func invalidAddressErrorTextSwapWithZcashAddress() {
        var state = AddressBook.State()
        state.context = .swap
        state.isValidZcashAddress = true
        #expect(state.invalidAddressErrorText == String(localizable: .swapAndPayAddressBookZcash))
    }

    @Test func invalidAddressErrorTextInvalidInSendContext() {
        var state = AddressBook.State()
        state.context = .send
        state.address = "garbage"
        state.isValidZcashAddress = false
        #expect(state.invalidAddressErrorText == String(localizable: .addressBookErrorInvalidAddress))
    }

    @Test func invalidAddressErrorTextNilWhenValid() {
        var state = AddressBook.State()
        state.context = .send
        state.address = "validaddr"
        state.isValidZcashAddress = true
        #expect(state.invalidAddressErrorText == nil)
    }

    @Test func saveButtonDisabledWhenNoChange() {
        #expect(AddressBook.State().isSaveButtonDisabled)
    }

    @Test func saveButtonEnabledForValidNewContact() {
        var state = AddressBook.State()
        state.context = .settings
        state.address = "validaddr"
        state.name = "Alice"
        state.isValidZcashAddress = true
        state.isValidForm = true
        #expect(!state.isSaveButtonDisabled)
    }
}
