#import <Foundation/Foundation.h>

// Point this at your own Plex Media Server, either by editing the line below or,
// to keep your own address out of the repo, by creating a "server.local" file
// next to build.sh containing just the URL (see the README).
#ifndef PLEX_SERVER
#define PLEX_SERVER   @"http://ipaddress:port"
#endif

#define PLEX_PRODUCT  @"PlexMini iPad"
#define PLEX_VERSION  @"2.0"
#define PLEX_PLATFORM @"iOS"
#define PLEX_DEVICE   @"iPad4"

// Strict percent-encoding for values interpolated into a URL query string.
// NSURL silently returns nil for the whole URL if any component contains a raw
// space or other reserved character, so every dynamic value must go through this.
NSString *PlexURLEncode(NSString *s);
