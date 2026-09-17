#import <Foundation/Foundation.h>

// Change this to point at your own Plex Media Server.
#define PLEX_SERVER   @"http://192.168.1.149:32400"

#define PLEX_PRODUCT  @"PlexMini iPad"
#define PLEX_VERSION  @"2.0"
#define PLEX_PLATFORM @"iOS"
#define PLEX_DEVICE   @"iPad4"

// Strict percent-encoding for values interpolated into a URL query string.
// NSURL silently returns nil for the whole URL if any component contains a raw
// space or other reserved character, so every dynamic value must go through this.
NSString *PlexURLEncode(NSString *s);
