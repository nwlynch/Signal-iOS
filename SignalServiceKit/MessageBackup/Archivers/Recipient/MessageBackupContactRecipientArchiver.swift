//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Archives ``SignalRecipient``s as ``BackupProto.Contact`` recipients.
public class MessageBackupContactRecipientArchiver: MessageBackupProtoArchiver {
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<RecipientId>

    private let blockingManager: MessageBackup.Shims.BlockingManager
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientHidingManager: RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let signalServiceAddressCache: SignalServiceAddressCache
    private let storyStore: StoryStore
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager

    public init(
        blockingManager: MessageBackup.Shims.BlockingManager,
        profileManager: MessageBackup.Shims.ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientHidingManager: RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        signalServiceAddressCache: SignalServiceAddressCache,
        storyStore: StoryStore,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager
    ) {
        self.blockingManager = blockingManager
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
        self.signalServiceAddressCache = signalServiceAddressCache
        self.storyStore = storyStore
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
    }

    func archiveAllContactRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        let whitelistedAddresses = Set(profileManager.allWhitelistedAddresses(tx: tx))
        let blockedAddresses = blockingManager.blockedAddresses(tx: tx)

        var errors = [ArchiveFrameError]()

        recipientDatabaseTable.enumerateAll(tx: tx) { recipient in
            guard
                let contactAddress = MessageBackup.ContactAddress(
                    aci: recipient.aci,
                    pni: recipient.pni,
                    e164: E164(recipient.phoneNumber?.stringValue)
                )
            else {
                // Skip but don't add to the list of errors.
                Logger.warn("Skipping empty recipient")
                return
            }

            guard !context.localIdentifiers.containsAnyOf(
                aci: recipient.aci,
                phoneNumber: E164(recipient.phoneNumber?.stringValue),
                pni: recipient.pni
            ) else {
                // Skip local user
                return
            }

            let recipientAddress = contactAddress.asArchivingAddress()

            let recipientId = context.assignRecipientId(to: recipientAddress)

            let storyContext = recipient.aci.map { self.storyStore.getOrCreateStoryContextAssociatedData(for: $0, tx: tx) }

            var contact = BackupProto.Contact(
                blocked: blockedAddresses.contains(recipient.address),
                visibility: { () -> BackupProto.Contact.Visibility in
                    if self.recipientHidingManager.isHiddenRecipient(recipient, tx: tx) {
                        if
                            let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx),
                            threadStore.hasPendingMessageRequest(thread: contactThread, tx: tx)
                        {
                            return .HIDDEN_MESSAGE_REQUEST
                        }

                        return .HIDDEN
                    } else {
                        return .VISIBLE
                    }
                }(),
                profileSharing: whitelistedAddresses.contains(recipient.address),
                hideStory: storyContext?.isHidden ?? false
            )
            contact.registration = { () -> BackupProto.Contact.Registration in
                if !recipient.isRegistered {
                    let unregisteredAtTimestamp = recipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp

                    return .notRegistered(BackupProto.Contact.NotRegistered(
                        unregisteredTimestamp: unregisteredAtTimestamp
                    ))
                }

                return .registered(BackupProto.Contact.Registered())
            }()

            contact.aci = recipient.aci.map(\.rawUUID.data)
            contact.pni = recipient.pni.map(\.rawUUID.data)
            contact.e164 = { () -> UInt64? in
                guard let phoneNumberString = recipient.phoneNumber?.stringValue else { return nil }
                return E164(phoneNumberString)?.uint64Value
            }()

            if let aci = recipient.aci {
                contact.username = usernameLookupManager.fetchUsername(
                    forAci: aci, transaction: tx
                )
            }

            let userProfile = self.profileManager.getUserProfile(for: recipient.address, tx: tx)
            contact.profileKey = userProfile?.profileKey.map(\.keyData)
            contact.profileGivenName = userProfile?.givenName
            contact.profileFamilyName = userProfile?.familyName

            Self.writeFrameToStream(
                stream,
                objectId: .contact(contactAddress),
                frameBuilder: {
                    var recipient = BackupProto.Recipient(id: recipientId.value)
                    recipient.destination = .contact(contact)

                    var frame = BackupProto.Frame()
                    frame.item = .recipient(recipient)
                    return frame
                }
            ).map { errors.append($0) }
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    func restoreContactRecipientProto(
        _ contactProto: BackupProto.Contact,
        recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, recipient.recipientId, line: line)])
        }

        let isRegistered: Bool
        let unregisteredTimestamp: UInt64?
        switch contactProto.registration {
        case nil:
            return .failure([.restoreFrameError(
                .invalidProtoData(.contactWithoutRegistrationInfo),
                recipient.recipientId
            )])
        case .notRegistered(let notRegisteredProto):
            isRegistered = false
            unregisteredTimestamp = notRegisteredProto.unregisteredTimestamp
        case .registered:
            isRegistered = true
            unregisteredTimestamp = nil
        }

        let aci: Aci?
        let pni: Pni?
        let e164: E164?
        let profileKey: OWSAES256Key?
        if let aciRaw = contactProto.aci {
            guard let aciUuid = UUID(data: aciRaw) else {
                return restoreFrameError(.invalidProtoData(.invalidAci(protoClass: BackupProto.Contact.self)))
            }
            aci = Aci.init(fromUUID: aciUuid)
        } else {
            aci = nil
        }
        if let pniRaw = contactProto.pni {
            guard let pniUuid = UUID(data: pniRaw) else {
                return restoreFrameError(.invalidProtoData(.invalidPni(protoClass: BackupProto.Contact.self)))
            }
            pni = Pni.init(fromUUID: pniUuid)
        } else {
            pni = nil
        }
        if let contactProtoE164 = contactProto.e164 {
            guard let protoE164 = E164(contactProtoE164) else {
                return restoreFrameError(.invalidProtoData(.invalidE164(protoClass: BackupProto.Contact.self)))
            }
            e164 = protoE164
        } else {
            e164 = nil
        }
        if let contactProtoProfileKeyData = contactProto.profileKey {
            guard let protoProfileKey = OWSAES256Key(data: contactProtoProfileKeyData) else {
                return restoreFrameError(.invalidProtoData(.invalidProfileKey(protoClass: BackupProto.Contact.self)))
            }
            profileKey = protoProfileKey
        } else {
            profileKey = nil
        }

        /// This check will fail if all these identifiers are `nil`.
        guard let backupContactAddress = MessageBackup.ContactAddress(
            aci: aci,
            pni: pni,
            e164: e164
        ) else {
            return restoreFrameError(.invalidProtoData(.contactWithoutIdentifiers))
        }
        context[recipient.recipientId] = .contact(backupContactAddress)

        let recipient = SignalRecipient.fromBackup(
            backupContactAddress,
            isRegistered: isRegistered,
            unregisteredAtTimestamp: unregisteredTimestamp
        )

        // Stop early if this is the local user. That shouldn't happen.
        let profileInsertableAddress: OWSUserProfile.InsertableAddress
        if let serviceId = backupContactAddress.aci ?? backupContactAddress.pni {
            profileInsertableAddress = OWSUserProfile.insertableAddress(
                serviceId: serviceId,
                localIdentifiers: context.localIdentifiers
            )
        } else if let phoneNumber = backupContactAddress.e164 {
            profileInsertableAddress = OWSUserProfile.insertableAddress(
                legacyPhoneNumberFromBackupRestore: phoneNumber,
                localIdentifiers: context.localIdentifiers
            )
        } else {
            return restoreFrameError(.developerError(OWSAssertionError("How did we have no identifiers after constructing a backup contact address?")))
        }
        switch profileInsertableAddress {
        case .localUser:
            return restoreFrameError(.invalidProtoData(.otherContactWithLocalIdentifiers))
        case .otherUser, .legacyUserPhoneNumberFromBackupRestore:
            break
        }

        recipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        /// No Backup code should be relying on the SSA cache, but once we've
        /// finished restoring and launched we want the cache to have accurate
        /// mappings based on the recipients we just restored.
        signalServiceAddressCache.updateRecipient(recipient, tx: tx)

        if
            let aci = recipient.aci,
            let username = contactProto.username
        {
            usernameLookupManager.saveUsername(username, forAci: aci, transaction: tx)
        }

        if contactProto.profileSharing {
            // Add to the whitelist.
            profileManager.addToWhitelist(recipient.address, tx: tx)
        }

        if contactProto.blocked {
            blockingManager.addBlockedAddress(recipient.address, tx: tx)
        }

        switch contactProto.visibility {
        case .HIDDEN, .HIDDEN_MESSAGE_REQUEST:
            /// Message-request state for hidden recipients isn't explicitly
            /// tracked on iOS, and instead is derived from their hidden state
            /// and the most-recent interactions in their 1:1 chat. So, for both
            /// of these cases all we need to do is hide the recipient.
            do {
                try recipientHidingManager.addHiddenRecipient(recipient, wasLocallyInitiated: false, tx: tx)
            } catch let error {
                return restoreFrameError(.databaseInsertionFailed(error))
            }
        case .VISIBLE:
            break
        }

        // We only need to active hide, since unhidden is the default.
        if contactProto.hideStory, let aci = backupContactAddress.aci {
            let storyContext = storyStore.getOrCreateStoryContextAssociatedData(for: aci, tx: tx)
            storyStore.updateStoryContext(storyContext, updateStorageService: false, isHidden: true, tx: tx)
        }

        profileManager.upsertOtherUserProfile(
            insertableAddress: profileInsertableAddress,
            givenName: contactProto.profileGivenName,
            familyName: contactProto.profileFamilyName,
            profileKey: profileKey,
            tx: tx
        )

        // TODO: [Backups] Enqueue a fetch of this contact's profile and download of their avatar (even if we have no profile key).

        return .success
    }
}
