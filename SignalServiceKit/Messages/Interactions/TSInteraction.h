//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/BaseModel.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class TSThread;

typedef NS_CLOSED_ENUM(NSInteger, OWSInteractionType) {
    OWSInteractionType_Unknown,
    OWSInteractionType_IncomingMessage,
    OWSInteractionType_OutgoingMessage,
    OWSInteractionType_Error,
    OWSInteractionType_Call,
    OWSInteractionType_Info,
    OWSInteractionType_TypingIndicator,
    OWSInteractionType_ThreadDetails,
    OWSInteractionType_UnreadIndicator,
    OWSInteractionType_DateHeader,
    OWSInteractionType_UnknownThreadWarning,
    OWSInteractionType_DefaultDisappearingMessageTimer
};

NSString *NSStringFromOWSInteractionType(OWSInteractionType value);

@protocol OWSPreviewText <NSObject>

- (NSString *)previewTextWithTransaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(previewText(transaction:));

@end

#pragma mark -

@interface TSInteraction : BaseModel

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;
- (instancetype)initWithGrdbId:(int64_t)grdbId uniqueId:(NSString *)uniqueId NS_UNAVAILABLE;

// Convenience initializer which is neither "designated" nor "unavailable".
- (instancetype)initWithUniqueId:(NSString *)uniqueId thread:(TSThread *)thread;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       timestamp:(uint64_t)timestamp
                          thread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       timestamp:(uint64_t)timestamp
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          thread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:));

// clang-format on

// --- CODE GENERATION MARKER

@property (nonatomic, readonly) NSString *uniqueThreadId;

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) uint64_t sortId;
@property (nonatomic, readonly) uint64_t receivedAtTimestamp;

@property (nonatomic, readonly) NSDate *receivedAtDate;
@property (nonatomic, readonly) NSDate *timestampDate;

@property (nonatomic, readonly) OWSInteractionType interactionType;

- (nullable TSThread *)threadWithTx:(SDSAnyReadTransaction *)tx NS_SWIFT_NAME(thread(tx:));

#pragma mark Utility Method

// "Dynamic" interactions are not messages or static events (like
// info messages, error messages, etc.).  They are interactions
// created, updated and deleted by the views.
//
// These include block offers, "add to contact" offers,
// unseen message indicators, etc.
@property (nonatomic, readonly) BOOL isDynamicInteraction;

- (void)replaceSortId:(uint64_t)sortId;

#if TESTABLE_BUILD
- (void)replaceTimestamp:(uint64_t)timestamp transaction:(SDSAnyWriteTransaction *)transaction;
- (void)replaceReceivedAtTimestamp:(uint64_t)receivedAtTimestamp NS_SWIFT_NAME(replaceReceivedAtTimestamp(_:));
- (void)replaceReceivedAtTimestamp:(uint64_t)receivedAtTimestamp transaction:(SDSAnyWriteTransaction *)transaction;
#endif

@end

@interface TSInteraction (Subclass)

// Timestamps are *almost* always immutable. The one exception is for placeholder interactions.
// After a certain amount of time, a placeholder becomes ineligible for replacement. The would-be
// replacement is just inserted natively.
//
// This breaks all sorts of assumptions we have of timestamps being unique. To workaround this,
// we decrement the timestamp on a failed placeholder. This ensures that both the placeholder
// error message and the would-be replacement can coexist.
@property (nonatomic, assign) uint64_t timestamp;

@end

NS_ASSUME_NONNULL_END
