//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSAttachmentStream.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "OWSError.h"
#import "OWSFileSystem.h"
#import "TSAttachmentPointer.h"
#import "UIImage+OWS.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSLoadedThumbnailSuccess)(OWSLoadedThumbnail *loadedThumbnail);

NSString *NSStringForAttachmentThumbnailQuality(TSAttachmentThumbnailQuality value)
{
    switch (value) {
        case TSAttachmentThumbnailQuality_Small:
            return @"Small";
        case TSAttachmentThumbnailQuality_Medium:
            return @"Medium";
        case TSAttachmentThumbnailQuality_MediumLarge:
            return @"MediumLarge";
        case TSAttachmentThumbnailQuality_Large:
            return @"Large";
    }
}

@interface TSAttachmentStream ()

// We only want to generate the file path for this attachment once, so that
// changes in the file path generation logic don't break existing attachments.
@property (nullable, nonatomic) NSString *localRelativeFilePath;

// These properties should only be accessed while synchronized on self.
//
// In pixels, not points.
@property (nullable, nonatomic) NSNumber *cachedImageWidth;
@property (nullable, nonatomic) NSNumber *cachedImageHeight;

// This property should only be accessed on the main thread.
@property (nullable, nonatomic) NSNumber *cachedAudioDurationSeconds;

@property (atomic, nullable) NSNumber *isValidImageCached;
@property (atomic, nullable) NSNumber *isValidVideoCached;
@property (atomic, nullable) NSNumber *isAnimatedCached;

@end

#pragma mark -

@implementation TSAttachmentStream

- (instancetype)initWithContentType:(NSString *)contentType
                          byteCount:(UInt32)byteCount
                     sourceFilename:(nullable NSString *)sourceFilename
                            caption:(nullable NSString *)caption
                     attachmentType:(TSAttachmentType)attachmentType
                     albumMessageId:(nullable NSString *)albumMessageId
{
    self = [super initAttachmentWithContentType:contentType
                                      byteCount:byteCount
                                 sourceFilename:sourceFilename
                                        caption:caption
                                 attachmentType:attachmentType
                                 albumMessageId:albumMessageId];
    if (!self) {
        return self;
    }

    // TSAttachmentStream doesn't have any "incoming vs. outgoing"
    // state, but this constructor is used only for new outgoing
    // attachments which haven't been uploaded yet.
    _isUploaded = NO;
    _creationTimestamp = [NSDate new];

    [self ensureFilePath];

    return self;
}

- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer transaction:(SDSAnyReadTransaction *)transaction
{
    // Once saved, this AttachmentStream will replace the AttachmentPointer in the attachments collection.
    self = [super initWithPointer:pointer transaction:transaction];
    if (!self) {
        return self;
    }

    OWSAssertDebug([NSObject isNullableObject:self.contentType equalTo:pointer.contentType]);

    // TSAttachmentStream doesn't have any "incoming vs. outgoing"
    // state, but this constructor is used only for new incoming
    // attachments which don't need to be uploaded.
    _isUploaded = YES;
    self.digest = pointer.digest;
    _creationTimestamp = [NSDate new];

    [self ensureFilePath];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // OWS105AttachmentFilePaths will ensure the file path is saved if necessary.
    [self ensureFilePath];

    // OWS105AttachmentFilePaths will ensure the creation timestamp is saved if necessary.
    if (!_creationTimestamp) {
        _creationTimestamp = [NSDate new];
    }

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                  albumMessageId:(nullable NSString *)albumMessageId
         attachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
                  attachmentType:(TSAttachmentType)attachmentType
                        blurHash:(nullable NSString *)blurHash
                       byteCount:(unsigned int)byteCount
                         caption:(nullable NSString *)caption
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(unsigned int)cdnNumber
                     contentType:(NSString *)contentType
                   encryptionKey:(nullable NSData *)encryptionKey
                        serverId:(unsigned long long)serverId
                  sourceFilename:(nullable NSString *)sourceFilename
                 uploadTimestamp:(unsigned long long)uploadTimestamp
                   videoDuration:(nullable NSNumber *)videoDuration
      cachedAudioDurationSeconds:(nullable NSNumber *)cachedAudioDurationSeconds
               cachedImageHeight:(nullable NSNumber *)cachedImageHeight
                cachedImageWidth:(nullable NSNumber *)cachedImageWidth
               creationTimestamp:(NSDate *)creationTimestamp
                          digest:(nullable NSData *)digest
                isAnimatedCached:(nullable NSNumber *)isAnimatedCached
                      isUploaded:(BOOL)isUploaded
              isValidImageCached:(nullable NSNumber *)isValidImageCached
              isValidVideoCached:(nullable NSNumber *)isValidVideoCached
           localRelativeFilePath:(nullable NSString *)localRelativeFilePath
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
                    albumMessageId:albumMessageId
           attachmentSchemaVersion:attachmentSchemaVersion
                    attachmentType:attachmentType
                          blurHash:blurHash
                         byteCount:byteCount
                           caption:caption
                            cdnKey:cdnKey
                         cdnNumber:cdnNumber
                       contentType:contentType
                     encryptionKey:encryptionKey
                          serverId:serverId
                    sourceFilename:sourceFilename
                   uploadTimestamp:uploadTimestamp
                     videoDuration:videoDuration];

    if (!self) {
        return self;
    }

    _cachedAudioDurationSeconds = cachedAudioDurationSeconds;
    _cachedImageHeight = cachedImageHeight;
    _cachedImageWidth = cachedImageWidth;
    _creationTimestamp = creationTimestamp;
    _digest = digest;
    _isAnimatedCached = isAnimatedCached;
    _isUploaded = isUploaded;
    _isValidImageCached = isValidImageCached;
    _isValidVideoCached = isValidVideoCached;
    _localRelativeFilePath = localRelativeFilePath;

    [self sdsFinalizeAttachmentStream];

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (void)sdsFinalizeAttachmentStream
{
    [self upgradeAttachmentSchemaVersionIfNecessary];
}

- (void)upgradeFromAttachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
{
    [super upgradeFromAttachmentSchemaVersion:attachmentSchemaVersion];

    if (attachmentSchemaVersion < 1) {
        // Older video attachments could incorrectly be marked as not
        // valid before we increased our size limits to allow 4k video.
        if (self.isValidVideoCached && !self.isValidVideoCached.boolValue) {
            self.isValidVideoCached = nil;
        }
    }
}

- (void)ensureFilePath
{
    if (self.localRelativeFilePath) {
        return;
    }

    NSString *attachmentsFolder = [[self class] attachmentsFolder];
    NSString *filePath = [MIMETypeUtil filePathForAttachment:self.uniqueId
                                                  ofMIMEType:self.contentType
                                              sourceFilename:self.sourceFilename
                                                    inFolder:attachmentsFolder];
    if (!filePath) {
        OWSFailDebug(@"Could not generate path for attachment.");
        return;
    }
    if (![filePath hasPrefix:attachmentsFolder]) {
        OWSFailDebug(@"Attachment paths should all be in the attachments folder.");
        return;
    }
    NSString *localRelativeFilePath = [filePath substringFromIndex:attachmentsFolder.length];
    if (localRelativeFilePath.length < 1) {
        OWSFailDebug(@"Empty local relative attachment paths.");
        return;
    }

    self.localRelativeFilePath = localRelativeFilePath;
    OWSAssertDebug(self.originalFilePath);
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return nil;
    }
    return [NSData dataWithContentsOfFile:filePath options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    OWSAssertDebug(data);

    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        *error = OWSErrorMakeAssertionError(@"Missing path for attachment.");
        return NO;
    }
    return [data writeToFile:filePath options:0 error:error];
}

- (BOOL)writeCopyingDataSource:(id<DataSource>)dataSource error:(NSError **)error
{
    OWSAssertDebug(dataSource);

    NSURL *_Nullable originalMediaURL = self.originalMediaURL;
    if (originalMediaURL == nil) {
        *error = OWSErrorMakeAssertionError(@"Missing URL for attachment.");
        return NO;
    }
    return [dataSource writeToUrl:originalMediaURL error:error];
}

- (BOOL)writeConsumingDataSource:(id<DataSource>)dataSource error:(NSError **)error
{
    OWSAssertDebug(dataSource);

    NSURL *_Nullable originalMediaURL = self.originalMediaURL;
    if (originalMediaURL == nil) {
        *error = OWSErrorMakeAssertionError(@"Missing URL for attachment.");
        return NO;
    }
    return [dataSource moveToUrlAndConsume:originalMediaURL error:error];
}

+ (NSString *)legacyAttachmentsDirPath
{
    return [[OWSFileSystem appDocumentDirectoryPath] stringByAppendingPathComponent:@"Attachments"];
}

+ (NSString *)sharedDataAttachmentsDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"Attachments"];
}

+ (NSString *)attachmentsFolder
{
    static NSString *attachmentsFolder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        attachmentsFolder = TSAttachmentStream.sharedDataAttachmentsDirPath;

        [OWSFileSystem ensureDirectoryExists:attachmentsFolder];
    });
    return attachmentsFolder;
}

- (nullable NSString *)originalFilePath
{
    if (!self.localRelativeFilePath) {
        OWSFailDebug(@"Attachment missing local file path.");
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

/// For new attachments, we create a folder based on the uniqueId where we store all attachment data.
/// Legacy attachments may have data stored directly in the `attachmentsFolder`.
- (nullable NSString *)uniqueIdAttachmentFolder
{
    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.uniqueId];
}

- (BOOL)ensureUniqueIdAttachmentFolder
{
    return [OWSFileSystem ensureDirectoryExists:self.uniqueIdAttachmentFolder];
}

- (nullable NSString *)audioWaveformPath
{
    if (!self.isAudioMimeType) {
        return nil;
    }

    return [self.uniqueIdAttachmentFolder stringByAppendingPathComponent:@"waveform.dat"];
}

- (nullable NSString *)legacyThumbnailPath
{
    NSString *filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Attachment missing local file path.");
        return nil;
    }

    if (!self.isImageMimeType && !self.isVideoMimeType && [self getAnimatedMimeType] == TSAnimatedMimeTypeNotAnimated) {
        return nil;
    }

    NSString *filename = filePath.lastPathComponent.stringByDeletingPathExtension;
    NSString *containingDir = filePath.stringByDeletingLastPathComponent;
    NSString *newFilename = [filename stringByAppendingString:@"-signal-ios-thumbnail"];

    return [[containingDir stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:@"jpg"];
}

- (NSString *)thumbnailsDirPath
{
    if (!self.localRelativeFilePath) {
        OWSFailDebug(@"Attachment missing local file path.");
        return nil;
    }

    // Thumbnails are written to the caches directory, so that iOS can
    // remove them if necessary.
    NSString *dirName = [NSString stringWithFormat:@"%@-thumbnails", self.uniqueId];
    return [OWSFileSystem.cachesDirectoryPath stringByAppendingPathComponent:dirName];
}

- (NSString *)pathForThumbnailDimensionPoints:(CGFloat)thumbnailDimensionPoints
{
    NSString *fileExtension = [OWSThumbnailService thumbnailFileExtensionForContentType:self.contentType];
    NSString *filename =
        [NSString stringWithFormat:@"thumbnail-%lu.%@", (unsigned long)thumbnailDimensionPoints, fileExtension];
    return [self.thumbnailsDirPath stringByAppendingPathComponent:filename];
}

- (nullable NSURL *)originalMediaURL
{
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (void)removeFile
{
    NSString *_Nullable thumbnailsDirPath = self.thumbnailsDirPath;
    if (thumbnailsDirPath && ![OWSFileSystem deleteFileIfExists:thumbnailsDirPath]) {
        OWSLogError(@"remove thumbnails dir failed.");
    }

    NSString *_Nullable legacyThumbnailPath = self.legacyThumbnailPath;
    if (legacyThumbnailPath && ![OWSFileSystem deleteFileIfExists:legacyThumbnailPath]) {
        OWSLogError(@"remove legacy thumbnail failed.");
    }

    NSString *_Nullable filePath = self.originalFilePath;
    OWSAssertDebug(filePath);
    if (filePath && ![OWSFileSystem deleteFileIfExists:filePath]) {
        OWSLogError(@"remove file failed");
    }

    // Remove the attachment specific directory and any associated files stored for this attachment.
    NSString *_Nullable attachmentFolder = self.uniqueIdAttachmentFolder;
    if (attachmentFolder && ![OWSFileSystem deleteFileIfExists:attachmentFolder]) {
        OWSFailDebug(@"remove unique attachment folder failed.");
    }
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];
    [MediaGalleryManager didInsertAttachmentStream:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self removeFile];
    [MediaGalleryManager didRemoveAttachmentStream:self transaction:transaction];
}

- (BOOL)isValidVisualMedia
{
    return [self isValidVisualMediaIgnoringSize:NO];
}

- (BOOL)isValidVisualMediaIgnoringSize:(BOOL)ignoreSize
{
    if (self.isImageMimeType && [self isValidImageIgnoringSize:ignoreSize]) {
        return YES;
    }

    if (self.isVideoMimeType && [self isValidVideoIgnoringSize:ignoreSize]) {
        return YES;
    }

    if ([self getAnimatedMimeType] != TSAnimatedMimeTypeNotAnimated && [self isValidImageIgnoringSize:ignoreSize]) {
        return YES;
    }

    return NO;
}

#pragma mark - Image Validation

- (BOOL)isValidImage
{
    return [self isValidImageIgnoringSize:NO];
}

- (BOOL)isValidImageIgnoringSize:(BOOL)ignoreSize
{
    OWSAssertDebug(self.isImageMimeType || [self getAnimatedMimeType] != TSAnimatedMimeTypeNotAnimated);

    BOOL result;
    BOOL didUpdateCache = NO;
    @synchronized(self) {
        if (!self.isValidImageCached) {
            self.isValidImageCached = @([NSData imageMetadataWithPath:self.originalFilePath
                                                             mimeType:self.contentType
                                                       ignoreFileSize:ignoreSize]
                                            .isValid);
            if (!self.isValidImageCached.boolValue) {
                OWSLogWarn(@"Invalid image.");
            }
            didUpdateCache = YES;
        }
        result = self.isValidImageCached.boolValue;
    }

    if (didUpdateCache && self.canAsyncUpdate) {
        [self applyChangeAsyncToLatestCopyWithChangeBlock:^(
            TSAttachmentStream *latestInstance) { latestInstance.isValidImageCached = @(result); }];
    }

    return result;
}

- (BOOL)canAsyncUpdate
{
    return !CurrentAppContext().isRunningTests;
}

- (BOOL)isValidVideo
{
    return [self isValidVideoIgnoringSize:NO];
}

- (BOOL)isValidVideoIgnoringSize:(BOOL)ignoreSize
{
    OWSAssertDebug(self.isVideoMimeType);

    BOOL result;
    BOOL didUpdateCache = NO;
    @synchronized(self) {
        if (!self.isValidVideoCached) {
            self.isValidVideoCached = @([OWSMediaUtils isValidVideoWithPath:self.originalFilePath
                                                                 ignoreSize:ignoreSize]);
            if (!self.isValidVideoCached) {
                OWSLogWarn(@"Invalid video.");
            }
            didUpdateCache = YES;
        }
        result = self.isValidVideoCached.boolValue;
    }

    if (didUpdateCache && self.canAsyncUpdate) {
        [self applyChangeAsyncToLatestCopyWithChangeBlock:^(
            TSAttachmentStream *latestInstance) { latestInstance.isValidVideoCached = @(result); }];
    }

    return result;
}

- (BOOL)isAnimatedContent
{
    BOOL result;
    BOOL didUpdateCache = NO;
    @synchronized(self) {
        if (!self.isAnimatedCached) {
            self.isAnimatedCached = @([self hasAnimatedImageContent]);
            didUpdateCache = YES;
        }
        result = self.isAnimatedCached.boolValue;
    }

    if (didUpdateCache && self.canAsyncUpdate) {
        [self applyChangeAsyncToLatestCopyWithChangeBlock:^(
            TSAttachmentStream *latestInstance) { latestInstance.isAnimatedCached = @(result); }];
    }

    return result;
}

- (BOOL)shouldBeRenderedByYY
{
    if ([MIMETypeUtil isDefinitelyAnimated:self.contentType]) {
        return YES;
    }
    return self.isAnimatedContent;
}

- (BOOL)hasAnimatedImageContent
{
    return [OWSVideoAttachmentDetection.sharedInstance attachmentStreamIsAnimated:self];
}

#pragma mark -

- (nullable UIImage *)originalImage
{
    if ([self isVideoMimeType]) {
        return [self videoStillImage];
    } else if ([self isImageMimeType] || [self getAnimatedMimeType] != TSAnimatedMimeTypeNotAnimated) {
        NSString *_Nullable originalFilePath = self.originalFilePath;
        if (!originalFilePath) {
            return nil;
        }
        if (![self isValidImage]) {
            return nil;
        }
        UIImage *_Nullable image;
        if (self.isWebpImageMimeType) {
            image = [[YYImage alloc] initWithContentsOfFile:originalFilePath];
        } else {
            image = [[UIImage alloc] initWithContentsOfFile:originalFilePath];
        }
        if (image == nil) {
            OWSFailDebug(
                @"Couldn't load original image: %d.", [OWSFileSystem fileOrFolderExistsAtPath:originalFilePath]);
        }
        return image;
    } else {
        return nil;
    }
}

- (nullable NSData *)validStillImageData
{
    if ([self isVideoMimeType]) {
        OWSFailDebug(@"isVideo was unexpectedly true");
        return nil;
    }
    if ([self getAnimatedMimeType] == TSAnimatedMimeTypeAnimated) {
        OWSFailDebug(@"isAnimated was unexpectedly true");
        return nil;
    }

    if (![NSData ows_isValidImageAtPath:self.originalFilePath mimeType:self.contentType]) {
        OWSFailDebug(@"skipping invalid image");
        return nil;
    }

    return [NSData dataWithContentsOfFile:self.originalFilePath];
}

- (nullable UIImage *)videoStillImage
{
    NSError *error;
    UIImage *_Nullable image = [OWSMediaUtils thumbnailForVideoAtPath:self.originalFilePath
                                                   maxDimensionPoints:[TSAttachmentStream thumbnailDimensionPointsLarge]
                                                                error:&error];
    if (error || !image) {
        OWSLogError(@"Could not create video still: %@.", error);
        return nil;
    }
    return image;
}

+ (void)deleteAttachmentsFromDisk
{
    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *fileURL = [NSURL fileURLWithPath:self.attachmentsFolder];
    NSArray<NSURL *> *contents = [fileManager contentsOfDirectoryAtURL:fileURL
                                            includingPropertiesForKeys:nil
                                                               options:0
                                                                 error:&error];

    if (error) {
        OWSFailDebug(@"failed to get contents of attachments folder: %@ with error: %@", self.attachmentsFolder, error);
        return;
    }

    for (NSURL *url in contents) {
        [fileManager removeItemAtURL:url error:&error];
        if (error) {
            OWSFailDebug(@"failed to remove item at path: %@ with error: %@", url, error);
        }
    }
}

- (CGSize)calculateImageSizePixels
{
    if ([self isVideoMimeType]) {
        if (![self isValidVideo]) {
            return CGSizeZero;
        }
        return [[self videoStillImage] pixelSize];
    } else if ([self isImageMimeType] || [self getAnimatedMimeType] != TSAnimatedMimeTypeNotAnimated) {
        // imageSizeForFilePath checks validity.
        return [NSData imageSizeForFilePath:self.originalFilePath mimeType:self.contentType];
    } else {
        return CGSizeZero;
    }
}

- (BOOL)shouldHaveImageSize
{
    return ([self isVideoMimeType] || [self isImageMimeType] ||
        [self getAnimatedMimeType] != TSAnimatedMimeTypeNotAnimated);
}

- (CGSize)imageSizePixels
{
    if (!self.shouldHaveImageSize) {
        OWSFailDebug(@"Content type does not have image sync.");
        return CGSizeZero;
    }

    @synchronized(self) {
        if (self.cachedImageWidth && self.cachedImageHeight) {
            return CGSizeMake(self.cachedImageWidth.floatValue, self.cachedImageHeight.floatValue);
        }

        CGSize imageSizePixels = [self calculateImageSizePixels];
        if (imageSizePixels.width <= 0 || imageSizePixels.height <= 0) {
            return CGSizeZero;
        }
        self.cachedImageWidth = @(imageSizePixels.width);
        self.cachedImageHeight = @(imageSizePixels.height);

        if (self.canAsyncUpdate) {
            [self applyChangeAsyncToLatestCopyWithChangeBlock:^(TSAttachmentStream *latestInstance) {
                latestInstance.cachedImageWidth = @(imageSizePixels.width);
                latestInstance.cachedImageHeight = @(imageSizePixels.height);
            }];
        }

        return imageSizePixels;
    }
}

- (CGSize)cachedMediaSize
{
    OWSAssertDebug(self.shouldHaveImageSize);

    @synchronized(self) {
        if (self.cachedImageWidth && self.cachedImageHeight) {
            return CGSizeMake(self.cachedImageWidth.floatValue, self.cachedImageHeight.floatValue);
        } else {
            return CGSizeZero;
        }
    }
}

#pragma mark - Update With...

- (void)applyChangeAsyncToLatestCopyWithChangeBlock:(void (^)(TSAttachmentStream *))changeBlock
{
    OWSAssertDebug(changeBlock);

    NSString *uniqueId = self.uniqueId;
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *tx) {
        // We load a new instance before using anyUpdateWithTransaction() since it
        // isn't thread-safe to mutate the current instance async.
        TSAttachmentStream *_Nullable latestInstance = [TSAttachmentStream anyFetchAttachmentStreamWithUniqueId:uniqueId
                                                                                                    transaction:tx];
        if (latestInstance == nil) {
            // This attachment has either not yet been saved or has been deleted; do
            // nothing. This isn't an error per se, but these race conditions should be
            // _very_ rare.
            //
            // An exception is incoming group avatar updates which we don't ever save.
            OWSLogWarn(@"Could not load attachment.");
            return;
        }
        changeBlock(latestInstance);
        [latestInstance anyOverwritingUpdateWithTransaction:tx];
    });
}

#pragma mark -

- (NSTimeInterval)calculateAudioDurationSeconds
{
    OWSAssertDebug([self isAudioMimeType]);

    if (CurrentAppContext().isRunningTests) {
        // Return an arbitrary non-zero value to avoid
        // expected exceptions in AVFoundation.
        return 1;
    }

    NSError *error;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.originalMediaURL error:&error];
    if (error && [error.domain isEqualToString:NSOSStatusErrorDomain]
        && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
        // Ignore "invalid audio file" errors.
        return 0;
    }
    if (!error) {
        [audioPlayer prepareToPlay];
        return [audioPlayer duration];
    } else {
        OWSLogError(@"Could not find audio duration: %@", self.originalMediaURL);
        return 0;
    }
}

- (NSTimeInterval)audioDurationSeconds
{
    @synchronized(self) {
        if (self.cachedAudioDurationSeconds) {
            return self.cachedAudioDurationSeconds.doubleValue;
        }

        NSTimeInterval audioDurationSeconds = [self calculateAudioDurationSeconds];
        self.cachedAudioDurationSeconds = @(audioDurationSeconds);

        if (self.canAsyncUpdate) {
            [self applyChangeAsyncToLatestCopyWithChangeBlock:^(TSAttachmentStream *latestInstance) {
                latestInstance.cachedAudioDurationSeconds = @(audioDurationSeconds);
            }];
        }

        return audioDurationSeconds;
    }
}

- (nullable AudioWaveform *)audioWaveform
{
    return [AudioWaveformManager audioWaveformForAttachment:self highPriority:NO];
}

- (nullable AudioWaveform *)highPriorityAudioWaveform
{
    return [AudioWaveformManager audioWaveformForAttachment:self highPriority:YES];
}

#pragma mark - Thumbnails

- (void)thumbnailImageWithSizeHint:(CGSize)sizeHint
                           success:(OWSThumbnailSuccess)success
                           failure:(OWSThumbnailFailure)failure
{
    CGFloat maxDimensionHint = MAX(sizeHint.width, sizeHint.height);
    CGFloat thumbnailDimensionPoints;
    if (maxDimensionHint <= TSAttachmentStream.thumbnailDimensionPointsSmall) {
        thumbnailDimensionPoints = TSAttachmentStream.thumbnailDimensionPointsSmall;
    } else if (maxDimensionHint <= TSAttachmentStream.thumbnailDimensionPointsMedium) {
        thumbnailDimensionPoints = TSAttachmentStream.thumbnailDimensionPointsMedium;
    } else {
        thumbnailDimensionPoints = [TSAttachmentStream thumbnailDimensionPointsLarge];
    }

    [self thumbnailImageWithThumbnailDimensionPoints:thumbnailDimensionPoints success:success failure:failure];
}

- (void)thumbnailImageWithQuality:(TSAttachmentThumbnailQuality)quality
                          success:(OWSThumbnailSuccess)success
                          failure:(OWSThumbnailFailure)failure
{
    CGFloat thumbnailDimensionPoints = [TSAttachmentStream thumbnailDimensionPointsForThumbnailQuality:quality];
    [self thumbnailImageWithThumbnailDimensionPoints:thumbnailDimensionPoints success:success failure:failure];
}

- (void)thumbnailImageWithThumbnailDimensionPoints:(CGFloat)thumbnailDimensionPoints
                                           success:(OWSThumbnailSuccess)success
                                           failure:(OWSThumbnailFailure)failure
{
    [self loadedThumbnailWithThumbnailDimensionPoints:thumbnailDimensionPoints
        success:^(OWSLoadedThumbnail *thumbnail) { DispatchMainThreadSafe(^{ success(thumbnail.image); }); }
        failure:^{ DispatchMainThreadSafe(^{ failure(); }); }];
}

- (void)loadedThumbnailWithThumbnailDimensionPoints:(CGFloat)thumbnailDimensionPoints
                                            success:(OWSLoadedThumbnailSuccess)success
                                            failure:(OWSThumbnailFailure)failure
{
    [self.thumbnailLoadingOperationQueue addOperationWithBlock:^{
        @autoreleasepool {
            if (!self.isValidVisualMedia) {
                // Never thumbnail (or try to use the original of) invalid media.
                OWSFailDebug(@"Invalid image.");
                failure();
                return;
            }

            CGSize originalSizePoints = self.imageSizePoints;
            if (self.imageSizePixels.width < 1 || self.imageSizePixels.height < 1) {
                failure();
                return;
            }

            if (originalSizePoints.width <= thumbnailDimensionPoints
                && originalSizePoints.height <= thumbnailDimensionPoints && self.isImageMimeType) {
                // There's no point in generating a thumbnail if the original is smaller than the
                // thumbnail size. Only do this for images. We still need to generate thumbnails
                // for videos.
                NSString *originalFilePath = self.originalFilePath;
                UIImage *_Nullable originalImage = self.originalImage;
                if (originalImage == nil) {
                    OWSFailDebug(@"originalImage was unexpectedly nil");
                    failure();
                } else {
                    success([[OWSLoadedThumbnail alloc] initWithImage:originalImage filePath:originalFilePath]);
                }
                return;
            }

            NSString *thumbnailPath = [self pathForThumbnailDimensionPoints:thumbnailDimensionPoints];
            if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailPath]) {
                UIImage *_Nullable image = [UIImage imageWithContentsOfFile:thumbnailPath];
                if (!image) {
                    OWSFailDebug(@"couldn't load image.");
                    failure();
                } else {
                    success([[OWSLoadedThumbnail alloc] initWithImage:image filePath:thumbnailPath]);
                }
                return;
            }

            [OWSThumbnailService.shared ensureThumbnailForAttachment:self
                                            thumbnailDimensionPoints:thumbnailDimensionPoints
                                                             success:success
                                                             failure:^(NSError *error) {
                                                                 OWSLogError(@"Failed to create thumbnail: %@", error);
                                                                 failure();
                                                             }];
        }
    }];
    return;
}

- (NSOperationQueue *)thumbnailLoadingOperationQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *operationQueue;
    dispatch_once(&onceToken, ^{
        operationQueue = [NSOperationQueue new];
        operationQueue.name = @"ThumbnailLoading";
        operationQueue.maxConcurrentOperationCount = 4;
    });
    return operationQueue;
}

- (nullable OWSLoadedThumbnail *)loadedThumbnailSyncWithDimensionPoints:(CGFloat)thumbnailDimensionPoints
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block OWSLoadedThumbnail *_Nullable asyncLoadedThumbnail = nil;
    [self loadedThumbnailWithThumbnailDimensionPoints:thumbnailDimensionPoints
        success:^(OWSLoadedThumbnail *thumbnail) {
            @synchronized(self) {
                asyncLoadedThumbnail = thumbnail;
            }
            dispatch_semaphore_signal(semaphore);
        }
        failure:^{ dispatch_semaphore_signal(semaphore); }];
    // Wait up to N seconds.
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    @synchronized(self) {
        return asyncLoadedThumbnail;
    }
}

- (nullable UIImage *)thumbnailImageSyncWithQuality:(TSAttachmentThumbnailQuality)quality
{
    CGFloat thumbnailDimensionPoints = [TSAttachmentStream thumbnailDimensionPointsForThumbnailQuality:quality];
    OWSLoadedThumbnail *_Nullable loadedThumbnail =
        [self loadedThumbnailSyncWithDimensionPoints:thumbnailDimensionPoints];
    if (!loadedThumbnail) {
        OWSLogInfo(@"Couldn't load %@ thumbnail sync.", NSStringForAttachmentThumbnailQuality(quality));
        return nil;
    }
    return loadedThumbnail.image;
}

- (nullable NSData *)thumbnailDataSmallSync
{
    OWSLoadedThumbnail *_Nullable loadedThumbnail =
        [self loadedThumbnailSyncWithDimensionPoints:TSAttachmentStream.thumbnailDimensionPointsSmall];
    if (!loadedThumbnail) {
        OWSLogInfo(@"Couldn't load small thumbnail sync.");
        return nil;
    }
    NSError *error;
    NSData *_Nullable data = [loadedThumbnail dataAndReturnError:&error];
    if (error || !data) {
        OWSFailDebug(@"Couldn't load thumbnail data: %@", error);
        return nil;
    }
    return data;
}

- (NSArray<NSString *> *)allSecondaryFilePaths
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];

    NSString *thumbnailsDirPath = self.thumbnailsDirPath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailsDirPath]) {
        NSError *error;
        NSArray<NSString *> *_Nullable fileNames =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:thumbnailsDirPath error:&error];
        if (error || !fileNames) {
            OWSFailDebug(@"contentsOfDirectoryAtPath failed with error: %@", error);
        } else {
            for (NSString *fileName in fileNames) {
                NSString *filePath = [thumbnailsDirPath stringByAppendingPathComponent:fileName];
                [result addObject:filePath];
            }
        }
    }

    NSString *_Nullable audioWaveformPath = self.audioWaveformPath;
    if (audioWaveformPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:audioWaveformPath]) {
        [result addObject:audioWaveformPath];
    }

    return result;
}

#pragma mark - Update With... Methods

- (void)updateAsUploadedWithEncryptionKey:(NSData *)encryptionKey
                                   digest:(NSData *)digest
                                 serverId:(UInt64)serverId
                                   cdnKey:(NSString *)cdnKey
                                cdnNumber:(UInt32)cdnNumber
                          uploadTimestamp:(unsigned long long)uploadTimestamp
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(encryptionKey.length > 0);
    OWSAssertDebug(digest.length > 0);
    OWSAssertDebug(serverId > 0 || cdnKey.length > 0);
    OWSAssertDebug(uploadTimestamp > 0);

    [self anyUpdateAttachmentStreamWithTransaction:transaction
                                             block:^(TSAttachmentStream *attachment) {
                                                 [attachment setEncryptionKey:encryptionKey];
                                                 [attachment setDigest:digest];
                                                 [attachment setServerId:serverId];
                                                 [attachment setCdnKey:cdnKey];
                                                 [attachment setCdnNumber:cdnNumber];
                                                 [attachment setUploadTimestamp:uploadTimestamp];
                                                 [attachment setIsUploaded:YES];
                                             }];
}

- (nullable TSAttachmentStream *)cloneAsThumbnail
{
    if (!self.isValidVisualMedia) {
        return nil;
    }

    NSString *thumbnailMimeType = [OWSThumbnailService thumbnailMimetypeForContentType:self.contentType];
    NSString *thumbnailFileExtension = [OWSThumbnailService thumbnailFileExtensionForContentType:self.contentType];

    NSData *_Nullable thumbnailData = self.thumbnailDataSmallSync;
    //  Only some media types have thumbnails
    if (!thumbnailData) {
        return nil;
    }

    // Copy the thumbnail to a new attachment.
    NSString *thumbnailName =
        [NSString stringWithFormat:@"quoted-thumbnail-%@.%@", self.sourceFilename, thumbnailFileExtension];
    TSAttachmentStream *thumbnailAttachment =
        [[TSAttachmentStream alloc] initWithContentType:thumbnailMimeType
                                              byteCount:(uint32_t)thumbnailData.length
                                         sourceFilename:thumbnailName
                                                caption:nil
                                         attachmentType:TSAttachmentTypeDefault
                                         albumMessageId:nil];

    NSError *error;
    BOOL success = [thumbnailAttachment writeData:thumbnailData error:&error];
    if (!success || error) {
        OWSLogError(@"Couldn't copy attachment data for message sent to self: %@.", error);
        return nil;
    }

    return thumbnailAttachment;
}

// MARK: Protobuf serialization

- (nullable SSKProtoAttachmentPointer *)buildProto
{
    BOOL isValidV1orV2 = self.serverId > 0;
    BOOL isValidV3 = (self.cdnKey.length > 0 && self.cdnNumber > 0);
    OWSAssertDebug(isValidV1orV2 || isValidV3);

    SSKProtoAttachmentPointerBuilder *builder = [SSKProtoAttachmentPointer builder];
    if (isValidV1orV2) {
        builder.cdnID = self.serverId;
    } else if (isValidV3) {
        builder.cdnKey = self.cdnKey;
        builder.cdnNumber = self.cdnNumber;
    }

    OWSAssertDebug(self.contentType.length > 0);
    builder.contentType = self.contentType;

    if (self.sourceFilename.length > 0) {
        builder.fileName = self.sourceFilename;
    }
    if (self.caption && self.caption.length > 0) {
        builder.caption = self.caption;
    }

    builder.size = self.byteCount;
    builder.key = self.encryptionKey;
    builder.digest = self.digest;

    if (self.attachmentType == TSAttachmentTypeVoiceMessage) {
        builder.flags = SSKProtoAttachmentPointerFlagsVoiceMessage;
    } else if (self.attachmentType == TSAttachmentTypeBorderless) {
        builder.flags = SSKProtoAttachmentPointerFlagsBorderless;
    } else if (self.attachmentType == TSAttachmentTypeGIF || self.isAnimatedContent) {
        builder.flags = SSKProtoAttachmentPointerFlagsGif;
    } else {
        builder.flags = 0;
    }

    if (self.blurHash.length > 0) {
        builder.blurHash = self.blurHash;
    }
    if (self.uploadTimestamp > 0) {
        builder.uploadTimestamp = self.uploadTimestamp;
    }

    if (self.shouldHaveImageSize) {
        CGSize imageSizePixels = self.imageSizePixels;
        if (imageSizePixels.width < NSIntegerMax && imageSizePixels.height < NSIntegerMax) {
            NSInteger imageWidth = (NSInteger)round(imageSizePixels.width);
            NSInteger imageHeight = (NSInteger)round(imageSizePixels.height);
            if (imageWidth > 0 && imageHeight > 0) {
                builder.width = (UInt32)imageWidth;
                builder.height = (UInt32)imageHeight;
            }
        }
    }

    return [builder buildInfallibly];
}

@end

NS_ASSUME_NONNULL_END
