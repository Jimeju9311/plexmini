#import <Foundation/Foundation.h>

// The video quality asked of the server's transcoder, persisted between launches.
//
// These files are HEVC and the iPad 4's A6X has no hardware HEVC decoder, so every
// playback is transcoded no matter what - the only question is what the server
// re-encodes *to*. The ceiling here is the A6X's H.264 decoder: High Profile up to
// Level 4.1, which is 1080p30. Sources run at 23.976 fps, so 1080p is safely inside
// it; going above 1080p would only cost bandwidth, since the screen is 2048x1536 and
// a 16:9 video fills at most 2048x1152.
@interface PlexQuality : NSObject

// Ordered best-first, each with a "label", "resolution" ("1920x1080") and
// "bitrate" (kbps, as an NSNumber).
+ (NSArray *)levels;

+ (NSInteger)selectedIndex;
+ (void)setSelectedIndex:(NSInteger)index;

+ (NSString *)currentResolution;
+ (NSInteger)currentBitrateKbps;
+ (NSString *)currentLabel;

@end
