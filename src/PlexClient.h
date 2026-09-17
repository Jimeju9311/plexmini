#import <UIKit/UIKit.h>

@interface PlexClient : NSObject
+ (NSString *)clientIdentifier;
+ (NSString *)authToken;
+ (void)setAuthToken:(NSString *)token;
+ (void)requestPin:(void (^)(NSNumber *pinId, NSString *code, NSError *error))completion;
+ (void)pollPin:(NSNumber *)pinId completion:(void (^)(NSString *authToken))completion;
+ (void)getJSON:(NSURL *)url completion:(void (^)(id json, NSError *error))completion;
+ (NSURL *)imageURLForThumb:(NSString *)thumbPath;
+ (void)loadImage:(NSURL *)url completion:(void (^)(UIImage *image))completion;
+ (void)fetchDetail:(NSString *)ratingKey completion:(void (^)(NSDictionary *item))completion;
+ (void)searchSubtitlesForRatingKey:(NSString *)ratingKey language:(NSString *)language completion:(void (^)(NSArray *results, NSError *error))completion;
+ (void)downloadSubtitleForRatingKey:(NSString *)ratingKey key:(NSString *)subtitleKey completion:(void (^)(BOOL ok))completion;
+ (void)setDefaultSubtitleStreamID:(NSNumber *)streamID forPartID:(NSNumber *)partID completion:(void (^)(BOOL ok))completion;
@end
