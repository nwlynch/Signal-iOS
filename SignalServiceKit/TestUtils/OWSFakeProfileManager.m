//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSFakeProfileManager.h"
#import "FunctionalUtil.h"
#import "NSString+SSK.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeProfileManager ()

@property (nonatomic, readonly) NSMutableDictionary<SignalServiceAddress *, OWSAES256Key *> *profileKeys;
@property (nonatomic, readonly) NSMutableSet<SignalServiceAddress *> *recipientWhitelist;
@property (nonatomic, readonly) NSMutableSet<NSString *> *threadWhitelist;
@property (nonatomic, readonly) OWSAES256Key *localProfileKey;
@property (nonatomic, nullable) NSString *localGivenName;
@property (nonatomic, nullable) NSString *localFamilyName;
@property (nonatomic, nullable) NSString *localFullName;
@property (nonatomic, nullable) NSData *localProfileAvatarData;
@property (nonatomic, nullable) NSArray<OWSUserProfileBadgeInfo *> *localProfileBadgeInfo;

@end

#pragma mark -

@implementation OWSFakeProfileManager

@synthesize localProfileKey = _localProfileKey;
@synthesize badgeStore = _badgeStore;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _profileKeys = [NSMutableDictionary new];
    _recipientWhitelist = [NSMutableSet new];
    _threadWhitelist = [NSMutableSet new];
    _stubbedStoriesCapabilitiesMap = [NSMutableDictionary new];
    _badgeStore = [[BadgeStore alloc] init];

    return self;
}

- (OWSAES256Key *)localProfileKey
{
    if (_localProfileKey == nil) {
        _localProfileKey = [OWSAES256Key generateRandomKey];
    }
    return _localProfileKey;
}

- (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)addressParam
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    return nil;
}

- (void)setProfileKeyData:(NSData *)profileKey
               forAddress:(SignalServiceAddress *)address
        userProfileWriter:(UserProfileWriter)userProfileWriter
            authedAccount:(nonnull AuthedAccount *)authedAccount
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKey];
    OWSAssert(key);
    self.profileKeys[address] = key;
}

- (void)fillInProfileKeysForAllProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)allProfileKeys
                  authoritativeProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)authoritativeProfileKeys
                         userProfileWriter:(UserProfileWriter)userProfileWriter
                             authedAccount:(AuthedAccount *)authedAccount
{
    for (SignalServiceAddress *address in allProfileKeys) {
        if (self.profileKeys[address] != nil) {
            continue;
        }
        NSData *_Nullable profileKeyData = allProfileKeys[address];
        OWSAssertDebug(profileKeyData);
        OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKeyData];
        self.profileKeys[address] = key;
    }
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
                 forAddress:(SignalServiceAddress *)address
          userProfileWriter:(UserProfileWriter)userProfileWriter
              authedAccount:(nonnull AuthedAccount *)authedAccount
                transaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(nonnull SignalServiceAddress *)address
          userProfileWriter:(UserProfileWriter)userProfileWriter
              authedAccount:(nonnull AuthedAccount *)authedAccount
                transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    return @"some fake profile name";
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return self.profileKeys[address].keyData;
}

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    return self.profileKeys[address];
}

- (void)normalizeRecipientInProfileWhitelist:(SignalRecipient *)recipient tx:(SDSAnyWriteTransaction *)tx
{
}

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.recipientWhitelist containsObject:address];
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.threadWhitelist containsObject:thread.uniqueId];
}

- (void)addUserToProfileWhitelist:(nonnull SignalServiceAddress *)address
                userProfileWriter:(UserProfileWriter)userProfileWriter
                      transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist addObject:address];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                 userProfileWriter:(UserProfileWriter)userProfileWriter
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist addObjectsFromArray:addresses];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    [self.recipientWhitelist removeObject:address];
}

- (void)removeUserFromProfileWhitelist:(nonnull SignalServiceAddress *)address
                     userProfileWriter:(UserProfileWriter)userProfileWriter
                           transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist removeObject:address];
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.threadWhitelist containsObject:groupId.hexadecimalString];
}

- (void)addGroupIdToProfileWhitelist:(nonnull NSData *)groupId
                   userProfileWriter:(UserProfileWriter)userProfileWriter
                         transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.threadWhitelist addObject:groupId.hexadecimalString];
}

- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
{
    [self.threadWhitelist removeObject:groupId.hexadecimalString];
}

- (void)removeGroupIdFromProfileWhitelist:(nonnull NSData *)groupId
                        userProfileWriter:(UserProfileWriter)userProfileWriter
                              transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.threadWhitelist removeObject:groupId.hexadecimalString];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self addGroupIdToProfileWhitelist:groupThread.groupModel.groupId
                         userProfileWriter:UserProfileWriter_LocalUser
                               transaction:transaction];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress
                      userProfileWriter:UserProfileWriter_LocalUser
                            transaction:transaction];
    }
}

- (void)fetchProfileForAddress:(nonnull SignalServiceAddress *)address
                 authedAccount:(nonnull AuthedAccount *)authedAccount
{
    // Do nothing.
}

- (void)warmCaches
{
    // Do nothing.
}

- (BOOL)recipientAddressIsStoriesCapable:(nonnull SignalServiceAddress *)address
                             transaction:(nonnull SDSAnyReadTransaction *)transaction
{
    NSNumber *_Nullable capability = self.stubbedStoriesCapabilitiesMap[address];
    if (capability == nil) {
        OWSFailDebug(@"unknown address %@ must be added to stubbedStoriesCapabilitiesMap.", address);
        return NO;
    }
    return capability.boolValue;
}

- (BOOL)hasLocalProfile
{
    return (self.localGivenName.length > 0 || self.localProfileAvatarImage != nil);
}

- (BOOL)hasProfileName
{
    return self.localGivenName.length > 0;
}

- (nullable UIImage *)localProfileAvatarImage
{
    NSData *_Nullable data = self.localProfileAvatarData;
    if (data == nil) {
        return nil;
    }

    return [UIImage imageWithData:data];
}

- (BOOL)localProfileExistsWithTransaction:(nonnull SDSAnyReadTransaction *)transaction
{
    return self.hasLocalProfile;
}

- (void)localProfileWasUpdated:(OWSUserProfile *)localUserProfile
{
    // Do nothing.
}

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size
{
    return nil;
}

- (BOOL)hasProfileAvatarData:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return NO;
}

- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction
{
    return nil;
}

- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                    downloadIfMissing:(BOOL)downloadIfMissing
                                        authedAccount:(nonnull AuthedAccount *)authedAccount
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    return nil;
}

- (void)didSendOrReceiveMessageFromAddress:(SignalServiceAddress *)address
                             authedAccount:(nonnull AuthedAccount *)authedAccount
                               transaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)reuploadLocalProfileWithAuthedAccount:(AuthedAccount *)authedAccount
{
    // Do nothing.
}

- (nullable NSURL *)writeAvatarDataToFile:(nonnull NSData *)avatarData
{
    return nil;
}

- (void)migrateWhitelistedGroupsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (NSArray<SignalServiceAddress *> *)allWhitelistedRegisteredAddressesWithTx:(SDSAnyReadTransaction *)tx
{
    return @[];
}

- (void)rotateProfileKeyUponRecipientHideWithTx:(SDSAnyWriteTransaction *)tx
{
    // Do nothing.
}

- (void)forceRotateLocalProfileKeyForGroupDepartureWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

@end

#endif

NS_ASSUME_NONNULL_END
