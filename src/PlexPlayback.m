#import "PlexPlayback.h"
#import "PlexClient.h"
#import "PlexConfig.h"
#import "PlexPlayerViewController.h"

@implementation PlexPlayback

+ (NSURL *)universalTranscodeURLForItem:(NSDictionary *)item
                                endpoint:(NSString *)endpoint
                               sessionId:(NSString *)sessionId
                       subtitleStreamID:(NSNumber *)subtitleStreamID
                          offsetSeconds:(NSInteger)offsetSeconds {
    NSString *ratingKey = item[@"ratingKey"];
    NSString *plexPath = [NSString stringWithFormat:@"/library/metadata/%@", ratingKey];
    NSString *encodedPath = PlexURLEncode(plexPath);
    NSString *clientId = PlexURLEncode([PlexClient clientIdentifier]);
    NSString *token = PlexURLEncode([PlexClient authToken] ?: @"");
    NSString *product = PlexURLEncode(PLEX_PRODUCT);

    // fastSeek=1 tells Plex to snap to the nearest keyframe instead of the exact requested
    // point, to start the transcode faster. On sources with widely/irregularly spaced
    // keyframes this can land many minutes past where the user actually dragged to (matches
    // what was reported: dragging to 9 landed at 18, to 12 landed at 25, to 16 at 27 - not a
    // fixed multiplier, just "wherever the next keyframe happens to be"). fastSeek=0 forces
    // an exact seek (decodes from the prior keyframe and re-encodes up to the exact point,
    // a little slower to start but lands precisely where requested).
    NSMutableString *urlStr = [NSMutableString stringWithFormat:
        @"%@/video/:/transcode/universal/%@?"
         "path=%@&mediaIndex=0&partIndex=0&protocol=hls&fastSeek=0"
         "&directPlay=0&directStream=0&subtitleSize=100&audioBoost=100"
         "&videoQuality=100&videoResolution=1280x720&maxVideoBitrate=8000"
         "&location=lan&session=%@&offset=%ld"
         "&X-Plex-Token=%@&X-Plex-Client-Identifier=%@"
         "&X-Plex-Product=%@&X-Plex-Platform=%@&X-Plex-Version=%@"
         "&X-Plex-Session-Identifier=%@",
        PLEX_SERVER, endpoint, encodedPath, sessionId, (long)offsetSeconds, token, clientId, product, PLEX_PLATFORM, PLEX_VERSION, sessionId];

    if (subtitleStreamID) {
        [urlStr appendFormat:@"&subtitleStreamID=%@", subtitleStreamID];
    }

    return [NSURL URLWithString:urlStr];
}

+ (void)playItem:(NSDictionary *)item
 subtitleStreamID:(NSNumber *)subtitleStreamID
fromViewController:(UIViewController *)presenter {
    PlexPlayerViewController *vc = [[PlexPlayerViewController alloc] init];
    vc.item = item;
    vc.subtitleStreamID = subtitleStreamID;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:vc animated:YES completion:nil];
}

@end
