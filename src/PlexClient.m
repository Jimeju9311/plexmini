#import "PlexClient.h"
#import "PlexConfig.h"

static NSString *const kTokenDefaultsKey = @"PlexAuthToken";
static NSString *const kClientIdDefaultsKey = @"PlexClientIdentifier";

@implementation PlexClient

+ (NSCache *)imageCache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 400;
    });
    return cache;
}

+ (NSString *)clientIdentifier {
    NSString *cid = [[NSUserDefaults standardUserDefaults] stringForKey:kClientIdDefaultsKey];
    if (!cid) {
        cid = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:cid forKey:kClientIdDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return cid;
}

+ (NSString *)authToken {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kTokenDefaultsKey];
}

+ (void)setAuthToken:(NSString *)token {
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:kTokenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)addPlexHeaders:(NSMutableURLRequest *)req {
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:PLEX_PRODUCT forHTTPHeaderField:@"X-Plex-Product"];
    [req setValue:PLEX_VERSION forHTTPHeaderField:@"X-Plex-Version"];
    [req setValue:PLEX_PLATFORM forHTTPHeaderField:@"X-Plex-Platform"];
    [req setValue:PLEX_DEVICE forHTTPHeaderField:@"X-Plex-Device"];
    [req setValue:[self clientIdentifier] forHTTPHeaderField:@"X-Plex-Client-Identifier"];
    NSString *token = [self authToken];
    if (token) {
        [req setValue:token forHTTPHeaderField:@"X-Plex-Token"];
    }
}

+ (void)getJSON:(NSURL *)url completion:(void (^)(id json, NSError *error))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [self addPlexHeaders:req];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || !data) {
                    completion(nil, error);
                    return;
                }
                NSError *jsonErr = nil;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                completion(json, jsonErr);
            });
        }];
    [task resume];
}

+ (void)postJSON:(NSURL *)url completion:(void (^)(id json, NSError *error))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [self addPlexHeaders:req];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || !data) {
                    completion(nil, error);
                    return;
                }
                NSError *jsonErr = nil;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                completion(json, jsonErr);
            });
        }];
    [task resume];
}

+ (void)putJSON:(NSURL *)url completion:(void (^)(id json, NSError *error))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"PUT";
    [self addPlexHeaders:req];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    completion(nil, error);
                    return;
                }
                id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                completion(json, nil);
            });
        }];
    [task resume];
}

+ (void)requestPin:(void (^)(NSNumber *, NSString *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:@"https://plex.tv/api/v2/pins?strong=false"];
    [self postJSON:url completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, nil, error);
            return;
        }
        completion(json[@"id"], json[@"code"], nil);
    }];
}

+ (void)pollPin:(NSNumber *)pinId completion:(void (^)(NSString *authToken))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://plex.tv/api/v2/pins/%@", pinId]];
    [self getJSON:url completion:^(id json, NSError *error) {
        if ([json isKindOfClass:[NSDictionary class]]) {
            id token = json[@"authToken"];
            if ([token isKindOfClass:[NSString class]] && [token length] > 0) {
                completion(token);
                return;
            }
        }
        completion(nil);
    }];
}

+ (NSURL *)imageURLForThumb:(NSString *)thumbPath {
    if (![thumbPath isKindOfClass:[NSString class]] || thumbPath.length == 0) return nil;
    NSString *token = PlexURLEncode([self authToken] ?: @"");
    NSString *urlStr = [NSString stringWithFormat:@"%@%@?X-Plex-Token=%@", PLEX_SERVER, thumbPath, token];
    return [NSURL URLWithString:urlStr];
}

+ (void)loadImage:(NSURL *)url completion:(void (^)(UIImage *image))completion {
    if (!url) { completion(nil); return; }
    UIImage *cached = [[self imageCache] objectForKey:url];
    if (cached) { completion(cached); return; }
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *img = data ? [UIImage imageWithData:data] : nil;
            if (img) [[self imageCache] setObject:img forKey:url];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(img);
            });
        }];
    [task resume];
}

+ (void)fetchDetail:(NSString *)ratingKey completion:(void (^)(NSDictionary *item))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/library/metadata/%@", PLEX_SERVER, ratingKey];
    [self getJSON:[NSURL URLWithString:urlStr] completion:^(id json, NSError *error) {
        NSArray *metadata = [json isKindOfClass:[NSDictionary class]] ? json[@"MediaContainer"][@"Metadata"] : nil;
        completion(([metadata isKindOfClass:[NSArray class]] && metadata.count > 0) ? metadata[0] : nil);
    }];
}

+ (void)searchSubtitlesForRatingKey:(NSString *)ratingKey language:(NSString *)language completion:(void (^)(NSArray *results, NSError *error))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/library/metadata/%@/subtitles?language=%@&hearingImpaired=0&forced=0",
        PLEX_SERVER, ratingKey, PlexURLEncode(language)];
    [self getJSON:[NSURL URLWithString:urlStr] completion:^(id json, NSError *error) {
        if (error) { completion(@[], error); return; }
        NSArray *results = [json isKindOfClass:[NSDictionary class]] ? json[@"MediaContainer"][@"Stream"] : nil;
        completion([results isKindOfClass:[NSArray class]] ? results : @[], nil);
    }];
}

+ (void)downloadSubtitleForRatingKey:(NSString *)ratingKey key:(NSString *)subtitleKey completion:(void (^)(BOOL ok))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/library/metadata/%@/subtitles?key=%@",
        PLEX_SERVER, ratingKey, PlexURLEncode(subtitleKey)];
    [self putJSON:[NSURL URLWithString:urlStr] completion:^(id json, NSError *error) {
        completion(error == nil);
    }];
}

// The transcode session's own "subtitleStreamID" query param turned out to be ignored -
// Plex auto-selects a subtitle per its own account-language logic regardless of what that
// param says (confirmed in the server log: it always resolved to the same stream no matter
// what was requested). Setting the file's *persisted default* subtitle stream is what that
// auto-select actually honors, so that is the only mechanism that really switches it.
+ (void)setDefaultSubtitleStreamID:(NSNumber *)streamID forPartID:(NSNumber *)partID completion:(void (^)(BOOL ok))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/library/parts/%@?subtitleStreamID=%@&allParts=1",
        PLEX_SERVER, partID, streamID];
    [self putJSON:[NSURL URLWithString:urlStr] completion:^(id json, NSError *error) {
        completion(error == nil);
    }];
}

@end
