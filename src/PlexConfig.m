#import "PlexConfig.h"

NSString *PlexURLEncode(NSString *s) {
    if (!s) return @"";
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}
