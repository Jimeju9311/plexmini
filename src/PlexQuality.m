#import "PlexQuality.h"

static NSString *const kQualityDefaultsKey = @"PlexVideoQuality";

@implementation PlexQuality

+ (NSArray *)levels {
    static NSArray *levels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        levels = @[
            @{@"label": @"1080p", @"resolution": @"1920x1080", @"bitrate": @20000},
            @{@"label": @"720p",  @"resolution": @"1280x720",  @"bitrate": @8000},
            @{@"label": @"480p",  @"resolution": @"854x480",   @"bitrate": @3000},
            @{@"label": @"360p",  @"resolution": @"640x360",   @"bitrate": @1500},
        ];
    });
    return levels;
}

+ (NSInteger)selectedIndex {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kQualityDefaultsKey]) {
        return 0; // 1080p: the panel is 2048x1536, so anything less is visibly upscaled
    }
    NSInteger index = [defaults integerForKey:kQualityDefaultsKey];
    if (index < 0 || index >= (NSInteger)[[self levels] count]) return 0;
    return index;
}

+ (void)setSelectedIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[[self levels] count]) return;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:kQualityDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSDictionary *)currentLevel {
    return [[self levels] objectAtIndex:[self selectedIndex]];
}

+ (NSString *)currentResolution {
    return [self currentLevel][@"resolution"];
}

+ (NSInteger)currentBitrateKbps {
    return [[self currentLevel][@"bitrate"] integerValue];
}

+ (NSString *)currentLabel {
    return [self currentLevel][@"label"];
}

@end
