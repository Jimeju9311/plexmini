#import <UIKit/UIKit.h>

@interface PlexPlayback : NSObject
// Builds either the "decision" or "start.m3u8" universal-transcode URL. Both must be
// called with the *same* sessionId and the *same* params, or Plex rejects start.m3u8
// with "session lacking decision for transcode of key ...". "offsetSeconds" restarts
// the transcode from a specific point - this is how seeking has to work, because
// letting AVPlayer seek natively inside a live-generated HLS stream asks the server
// for segments/timestamps it never generated, which comes back as unparsable data.
+ (NSURL *)universalTranscodeURLForItem:(NSDictionary *)item
                                endpoint:(NSString *)endpoint
                               sessionId:(NSString *)sessionId
                       subtitleStreamID:(NSNumber *)subtitleStreamID
                          offsetSeconds:(NSInteger)offsetSeconds;
+ (void)playItem:(NSDictionary *)item
 subtitleStreamID:(NSNumber *)subtitleStreamID
fromViewController:(UIViewController *)presenter;
@end
