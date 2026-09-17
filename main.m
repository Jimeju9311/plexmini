#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

#define PLEX_SERVER   @"http://192.168.1.149:32400"
#define PLEX_PRODUCT  @"PlexMini iPad"
#define PLEX_VERSION  @"2.0"
#define PLEX_PLATFORM @"iOS"
#define PLEX_DEVICE   @"iPad4"

static NSString *const kTokenDefaultsKey = @"PlexAuthToken";
static NSString *const kClientIdDefaultsKey = @"PlexClientIdentifier";

// Strict percent-encoding for values interpolated into a URL query string.
// NSURL silently returns nil for the whole URL if any component contains a raw
// space or other reserved character, so every dynamic value must go through this.
static NSString *PlexURLEncode(NSString *s) {
    if (!s) return @"";
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

@interface SubtitleSearchResultsViewController : UITableViewController
@property (nonatomic, copy) NSString *ratingKey;
@property (nonatomic, copy) NSArray *results;
@property (nonatomic, copy) void (^onDownloaded)(void);
@end

@interface SubtitlePickerViewController : UITableViewController
@property (nonatomic, copy) NSString *ratingKey;
@property (nonatomic, copy) NSArray *existingStreams; // Stream dicts with streamType == 3
@property (nonatomic, strong) NSNumber *selectedStreamID; // @0 = none, @(id) = a specific stream
@property (nonatomic, copy) void (^onSelect)(NSNumber *streamID);
@end

@interface PlexDetailViewController : UIViewController
@property (nonatomic, copy) NSDictionary *item;
@property (nonatomic, strong) NSDictionary *fullItem;
@property (nonatomic, strong) NSNumber *selectedSubtitleStreamID;
@property (nonatomic, strong) NSNumber *partId;
@property (nonatomic, strong) UIImageView *backdrop;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UITextView *summaryView;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *subsButton;
@end

@interface PlexPlayerViewController : UIViewController
@property (nonatomic, copy) NSDictionary *item;
@property (nonatomic, strong) NSNumber *subtitleStreamID;
@end

#pragma mark - PlexClient

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

#pragma mark - Link (PIN) View Controller

@interface LinkViewController : UIViewController
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) void (^onLinked)(void);
@end

@implementation LinkViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.text = @"Vincula esta app con tu cuenta Plex.\nEntra en plex.tv/link desde cualquier navegador\ny escribe este codigo:";
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.textColor = [UIColor whiteColor];
    self.hintLabel.font = [UIFont systemFontOfSize:18];
    [self.view addSubview:self.hintLabel];

    self.codeLabel = [[UILabel alloc] init];
    self.codeLabel.text = @"----";
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    self.codeLabel.textColor = [UIColor colorWithRed:0.90 green:0.65 blue:0.13 alpha:1];
    self.codeLabel.font = [UIFont boldSystemFontOfSize:56];
    [self.view addSubview:self.codeLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];

    [self requestNewPin];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.hintLabel.frame = CGRectMake(40, b.size.height * 0.32, b.size.width - 80, 90);
    self.codeLabel.frame = CGRectMake(20, CGRectGetMaxY(self.hintLabel.frame) + 20, b.size.width - 40, 70);
    self.spinner.frame = CGRectMake(0, CGRectGetMaxY(self.codeLabel.frame) + 20, b.size.width, 30);
}

- (void)requestNewPin {
    [PlexClient requestPin:^(NSNumber *pinId, NSString *code, NSError *error) {
        if (!pinId) {
            self.codeLabel.text = @"ERROR";
            self.hintLabel.text = [NSString stringWithFormat:@"No se pudo contactar a plex.tv\n%@\nReintentando...", error.localizedDescription ?: @""];
            [self performSelector:@selector(requestNewPin) withObject:nil afterDelay:8.0];
            return;
        }
        self.codeLabel.text = code;
        [self.pollTimer invalidate];
        self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 target:self selector:@selector(checkPin:) userInfo:pinId repeats:YES];
    }];
}

- (void)checkPin:(NSTimer *)timer {
    NSNumber *pinId = timer.userInfo;
    [PlexClient pollPin:pinId completion:^(NSString *authToken) {
        if (authToken) {
            [timer invalidate];
            [PlexClient setAuthToken:authToken];
            if (self.onLinked) self.onLinked();
        }
    }];
}

@end

#pragma mark - Custom cell with thumbnail

@interface PlexCell : UITableViewCell
@property (nonatomic, strong) NSURL *loadingURL;
@end

@implementation PlexCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        self.textLabel.textColor = [UIColor whiteColor];
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.clipsToBounds = YES;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        self.selectedBackgroundView = bg;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = self.contentView.bounds.size.height - 8;
    self.imageView.frame = CGRectMake(8, 4, side * 0.68, side);
    CGFloat textX = CGRectGetMaxX(self.imageView.frame) + 12;
    self.textLabel.frame = CGRectMake(textX, self.textLabel.frame.origin.y, self.contentView.bounds.size.width - textX - 30, self.textLabel.frame.size.height);
    self.detailTextLabel.frame = CGRectMake(textX, self.detailTextLabel.frame.origin.y, self.contentView.bounds.size.width - textX - 30, self.detailTextLabel.frame.size.height);
}

@end

#pragma mark - Library list (sections and items, reused for both levels)

@interface PlexListViewController : UITableViewController
@property (nonatomic, copy) NSString *fetchPath;   // e.g. /library/sections  or /library/sections/1/all
@property (nonatomic, copy) NSArray *items;         // array of NSDictionary (Directory/Video entries)
@property (nonatomic, assign) BOOL isTopLevel;      // YES only for the root /library/sections screen
@end

@implementation PlexListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.rowHeight = 96;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.tableView registerClass:[PlexCell class] forCellReuseIdentifier:@"cell"];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
    self.navigationItem.rightBarButtonItem = refresh;
    [self reload];
}

- (void)reload {
    NSString *urlStr = [NSString stringWithFormat:@"%@%@", PLEX_SERVER, self.fetchPath];
    [PlexClient getJSON:[NSURL URLWithString:urlStr] completion:^(id json, NSError *error) {
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                message:[NSString stringWithFormat:@"No se pudo cargar: %@", error.localizedDescription]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        NSDictionary *container = json[@"MediaContainer"];
        NSArray *directory = container[@"Directory"];
        NSArray *metadata = container[@"Metadata"];
        self.items = directory ?: metadata ?: @[];
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (NSString *)subtitleForItem:(NSDictionary *)item {
    NSString *type = item[@"type"];
    if ([type isEqualToString:@"episode"]) {
        NSNumber *season = item[@"parentIndex"];
        NSNumber *episode = item[@"index"];
        return [NSString stringWithFormat:@"T%@E%@", season ?: @0, episode ?: @0];
    }
    if ([type isEqualToString:@"movie"]) {
        NSNumber *year = item[@"year"];
        return year ? [year stringValue] : @"";
    }
    NSNumber *count = item[@"leafCount"] ?: item[@"childCount"];
    if (count) return [NSString stringWithFormat:@"%@ elementos", count];
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PlexCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *item = self.items[indexPath.row];
    cell.textLabel.text = item[@"title"] ?: @"(sin titulo)";
    cell.detailTextLabel.text = [self subtitleForItem:item];
    cell.imageView.image = nil;

    NSString *thumb = item[@"thumb"] ?: item[@"parentThumb"] ?: item[@"grandparentThumb"];
    NSURL *imgURL = [PlexClient imageURLForThumb:thumb];
    cell.loadingURL = imgURL;
    [PlexClient loadImage:imgURL completion:^(UIImage *image) {
        if ([cell.loadingURL isEqual:imgURL]) {
            cell.imageView.image = image;
            [cell setNeedsLayout];
        }
    }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];

    if (self.isTopLevel) {
        NSString *key = item[@"key"];
        PlexListViewController *next = [[PlexListViewController alloc] init];
        next.title = item[@"title"];
        next.fetchPath = [NSString stringWithFormat:@"/library/sections/%@/all", key];
        next.isTopLevel = NO;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    NSString *type = item[@"type"];
    if ([type isEqualToString:@"show"] || [type isEqualToString:@"season"]) {
        // Prefer the item's own "key" - Plex already gives a ready-to-use path there
        // (e.g. "/library/metadata/555/allLeaves" for a virtual "All episodes" node
        // on a flattened show, which has no ratingKey/children of its own). Only fall
        // back to building "/library/metadata/{ratingKey}/children" when "key" is
        // missing or isn't a real path.
        NSString *key = item[@"key"];
        NSString *fetchPath = nil;
        if ([key isKindOfClass:[NSString class]] && [key hasPrefix:@"/"]) {
            fetchPath = key;
        } else {
            id ratingKey = item[@"ratingKey"];
            if (ratingKey) {
                fetchPath = [NSString stringWithFormat:@"/library/metadata/%@/children", ratingKey];
            }
        }
        if (!fetchPath) {
            return; // malformed entry, nothing sensible to navigate to
        }
        PlexListViewController *next = [[PlexListViewController alloc] init];
        next.title = item[@"title"];
        next.fetchPath = fetchPath;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    PlexDetailViewController *detail = [[PlexDetailViewController alloc] init];
    detail.item = item;
    [self.navigationController pushViewController:detail animated:YES];
}

@end

#pragma mark - Shared playback pipeline (decision -> start.m3u8 -> cleanup)

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

#pragma mark - Custom player (seeking restarts the transcode at the new offset)

static UIColor *PlexAccentColor(void) {
    return [UIColor colorWithRed:0.90 green:0.65 blue:0.13 alpha:1];
}

static UIButton *PlexTextButton(NSString *text, CGFloat fontSize) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightMedium];
    b.backgroundColor = [UIColor clearColor];
    return b;
}

// Hand-drawn vector icons matching the reference Plex player layout - never unicode
// symbol glyphs (some render as full-color emoji on Apple platforms, e.g. "⏸").
typedef NS_ENUM(NSInteger, PlexIconKind) {
    PlexIconPlay,
    PlexIconPause,
    PlexIconClose,
    PlexIconSubtitles,
    PlexIconSettings
};

static UIImage *PlexIconImage(PlexIconKind kind, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);

    switch (kind) {
        case PlexIconPlay: {
            CGFloat inset = size * 0.28;
            UIBezierPath *tri = [UIBezierPath bezierPath];
            [tri moveToPoint:CGPointMake(inset, size * 0.18)];
            [tri addLineToPoint:CGPointMake(inset, size * 0.82)];
            [tri addLineToPoint:CGPointMake(size - inset * 0.7, size * 0.5)];
            [tri closePath];
            [tri fill];
            break;
        }
        case PlexIconPause: {
            CGFloat barW = size * 0.16;
            CGFloat gap = size * 0.16;
            CGFloat barH = size * 0.6;
            CGFloat y = (size - barH) / 2.0;
            CGFloat totalW = barW * 2 + gap;
            CGFloat startX = (size - totalW) / 2.0;
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(startX, y, barW, barH) cornerRadius:barW * 0.25] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(startX + barW + gap, y, barW, barH) cornerRadius:barW * 0.25] fill];
            break;
        }
        case PlexIconClose: {
            CGContextSetLineWidth(ctx, size * 0.09);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGFloat m = size * 0.28;
            CGContextMoveToPoint(ctx, m, m);
            CGContextAddLineToPoint(ctx, size - m, size - m);
            CGContextMoveToPoint(ctx, size - m, m);
            CGContextAddLineToPoint(ctx, m, size - m);
            CGContextStrokePath(ctx);
            break;
        }
        case PlexIconSubtitles: {
            CGFloat inset = size * 0.10;
            UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(inset, size * 0.22, size - inset * 2, size * 0.56) cornerRadius:size * 0.08];
            box.lineWidth = size * 0.08;
            [[UIColor whiteColor] setStroke];
            [box stroke];
            CGFloat lineY1 = size * 0.40, lineY2 = size * 0.58;
            CGContextSetLineWidth(ctx, size * 0.07);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGContextMoveToPoint(ctx, size * 0.24, lineY1);
            CGContextAddLineToPoint(ctx, size * 0.50, lineY1);
            CGContextMoveToPoint(ctx, size * 0.24, lineY2);
            CGContextAddLineToPoint(ctx, size * 0.70, lineY2);
            CGContextStrokePath(ctx);
            break;
        }
        case PlexIconSettings: {
            CGPoint center = CGPointMake(size / 2.0, size / 2.0);
            CGFloat outerR = size * 0.42;
            CGFloat innerR = size * 0.22;
            CGFloat toothW = size * 0.16;
            CGFloat toothH = size * 0.14;
            NSInteger teeth = 8;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, center.x, center.y);
            for (NSInteger i = 0; i < teeth; i++) {
                CGContextFillRect(ctx, CGRectMake(-toothW / 2.0, -outerR - toothH / 2.0, toothW, toothH));
                CGContextRotateCTM(ctx, 2.0 * M_PI / teeth);
            }
            CGContextRestoreGState(ctx);
            UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:center radius:(outerR + innerR) / 2.0
                startAngle:0 endAngle:2 * M_PI clockwise:YES];
            ring.lineWidth = outerR - innerR;
            [[UIColor whiteColor] setStroke];
            [ring stroke];
            break;
        }
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIButton *PlexIconButton(PlexIconKind kind, CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:PlexIconImage(kind, size) forState:UIControlStateNormal];
    b.backgroundColor = [UIColor clearColor];
    return b;
}

// Circular translucent buttons matching the reference layout's transport controls
// (skip-back/play-pause/skip-forward sit on a dark circular disc in real Plex).
static UIButton *PlexCircleIconButton(PlexIconKind kind, CGFloat iconSize, CGFloat diameter) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:PlexIconImage(kind, iconSize) forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.75];
    b.layer.cornerRadius = diameter / 2.0;
    return b;
}

static UIButton *PlexCircleTextButton(NSString *text, CGFloat fontSize, CGFloat diameter) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.75];
    b.layer.cornerRadius = diameter / 2.0;
    return b;
}

@interface PlexPlayerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, assign) NSInteger seekGeneration;
@property (nonatomic, strong) NSNumber *lastNonZeroSubtitleStreamID;
@property (nonatomic, copy) NSArray *subtitleStreams;
@property (nonatomic, strong) NSNumber *partId;
@property (nonatomic, strong) UIButton *subtitlesButton;
@property (nonatomic, assign) NSInteger durationSeconds;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) id failureObserver;
@property (nonatomic, strong) NSTimer *cleanupPoll;
@property (nonatomic, strong) NSTimer *autoHideTimer;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *centerControls;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) CAGradientLayer *topGradient;
@property (nonatomic, strong) CAGradientLayer *bottomGradient;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *skipBackButton;
@property (nonatomic, strong) UIButton *skipForwardButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@end

@implementation PlexPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.sessionId = [[NSUUID UUID] UUIDString];
    self.durationSeconds = [self.item[@"duration"] integerValue] / 1000;

    // --- top bar: title + metadata line on the left, close "X" on the right (matches the
    // reference Plex layout, minus its cast/PiP buttons which don't apply on this device) ---
    self.topBar = [[UIView alloc] init];
    [self.view addSubview:self.topBar];
    self.topGradient = [CAGradientLayer layer];
    self.topGradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.6].CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor];
    [self.topBar.layer addSublayer:self.topGradient];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    self.titleLabel.text = [self playerTitleText];
    [self.topBar addSubview:self.titleLabel];

    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    self.metaLabel.font = [UIFont systemFontOfSize:14];
    self.metaLabel.text = [self playerMetaText];
    [self.topBar addSubview:self.metaLabel];

    self.closeButton = PlexIconButton(PlexIconClose, 16);
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.closeButton];

    // --- center transport row: circular translucent buttons like the reference ---
    self.centerControls = [[UIView alloc] init];
    [self.view addSubview:self.centerControls];

    self.skipBackButton = PlexCircleTextButton(@"-10", 15, 52);
    [self.skipBackButton addTarget:self action:@selector(skipBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.centerControls addSubview:self.skipBackButton];

    self.playPauseButton = PlexCircleIconButton(PlexIconPause, 30, 74);
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.centerControls addSubview:self.playPauseButton];

    self.skipForwardButton = PlexCircleTextButton(@"+10", 15, 52);
    [self.skipForwardButton addTarget:self action:@selector(skipForwardTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.centerControls addSubview:self.skipForwardButton];

    // --- row above the scrub bar: subtitles toggle + settings (opens full subtitle picker) ---
    self.subtitlesButton = PlexIconButton(PlexIconSubtitles, 22);
    self.subtitlesButton.alpha = 0.4; // dimmed = off; full opacity = on
    [self.subtitlesButton addTarget:self action:@selector(subtitlesToggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.subtitlesButton];
    if (self.subtitleStreamID && self.subtitleStreamID.integerValue != 0) {
        self.lastNonZeroSubtitleStreamID = self.subtitleStreamID;
        self.subtitlesButton.alpha = 1.0;
    }
    // Fetching which subtitle tracks exist is async - disable the toggle until it actually
    // knows, otherwise tapping it in that window wrongly says "no subtitles" even when the
    // file has some, just because the answer hadn't arrived yet.
    self.subtitlesButton.enabled = NO;
    [self loadSubtitleStreams];

    self.settingsButton = PlexIconButton(PlexIconSettings, 22);
    [self.settingsButton addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.settingsButton];

    // --- bottom: scrub bar with time labels either side ---
    self.bottomBar = [[UIView alloc] init];
    [self.view addSubview:self.bottomBar];
    self.bottomGradient = [CAGradientLayer layer];
    self.bottomGradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.7].CGColor];
    [self.bottomBar.layer addSublayer:self.bottomGradient];

    self.elapsedLabel = [self timeLabelAligned:NSTextAlignmentLeft];
    self.remainingLabel = [self timeLabelAligned:NSTextAlignmentRight];
    [self.bottomBar addSubview:self.elapsedLabel];
    [self.bottomBar addSubview:self.remainingLabel];

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = 0;
    self.slider.maximumValue = MAX(self.durationSeconds, 1);
    self.slider.minimumTrackTintColor = PlexAccentColor();
    self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.25];
    [self.slider setThumbImage:[self sliderThumbImage] forState:UIControlStateNormal];
    [self.slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [self.slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpOutside];
    [self.slider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.bottomBar addSubview:self.slider];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.userInteractionEnabled = NO; // must never be able to steal a tap meant for the controls under it
    [self.view addSubview:self.spinner];

    // This spans the whole screen to let a tap anywhere show/hide the chrome, but by default
    // a UIGestureRecognizer CANCELS the touch it recognized before it reaches the view under
    // it - so every button and the slider were fighting this for every single tap/drag. That
    // is what made the scrub bar land at the wrong spot and made "CC"/settings do nothing
    // (or just toggle the chrome instead of firing their own action). This is the actual fix.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(videoTapped)];
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];

    [self startAtOffsetSeconds:0];
    [self scheduleAutoHide];
}

- (UILabel *)timeLabelAligned:(NSTextAlignment)alignment {
    UILabel *l = [[UILabel alloc] init];
    l.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    l.font = [UIFont systemFontOfSize:12];
    l.textAlignment = alignment;
    return l;
}

// Matches the reference layout: big title is just the episode/movie name, with season,
// episode, show and duration folded into a secondary line underneath instead.
- (NSString *)playerTitleText {
    return self.item[@"title"] ?: @"";
}

- (NSString *)playerMetaText {
    NSInteger minutes = self.durationSeconds / 60;
    NSString *type = self.item[@"type"];
    if ([type isEqualToString:@"episode"]) {
        return [NSString stringWithFormat:@"S%@ - E%@ - %@ - %ld min",
            self.item[@"parentIndex"] ?: @0, self.item[@"index"] ?: @0,
            self.item[@"grandparentTitle"] ?: @"", (long)minutes];
    }
    id year = self.item[@"year"];
    if (year) return [NSString stringWithFormat:@"%@ - %ld min", year, (long)minutes];
    return [NSString stringWithFormat:@"%ld min", (long)minutes];
}

#pragma mark Subtitle on/off toggle

- (void)loadSubtitleStreams {
    NSString *ratingKey = self.item[@"ratingKey"];
    __weak typeof(self) weakSelf = self;
    [PlexClient fetchDetail:[NSString stringWithFormat:@"%@", ratingKey] completion:^(NSDictionary *full) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.subtitlesButton.enabled = YES; // always, even if the fetch below fails - never leave it stuck disabled
        if (!full) return;
        NSArray *media = full[@"Media"];
        NSArray *parts = [media isKindOfClass:[NSArray class]] && media.count > 0 ? media[0][@"Part"] : nil;
        NSDictionary *part = [parts isKindOfClass:[NSArray class]] && parts.count > 0 ? parts[0] : nil;
        NSArray *streams = part[@"Stream"];
        strongSelf.partId = part[@"id"];
        NSMutableArray *subs = [NSMutableArray array];
        if ([streams isKindOfClass:[NSArray class]]) {
            for (NSDictionary *s in streams) {
                if ([s[@"streamType"] integerValue] == 3) [subs addObject:s];
            }
        }
        strongSelf.subtitleStreams = subs;
        if (!strongSelf.lastNonZeroSubtitleStreamID && subs.count > 0) {
            strongSelf.lastNonZeroSubtitleStreamID = subs[0][@"id"];
        }
    }];
}

- (void)subtitlesToggleTapped {
    BOOL currentlyOn = self.subtitleStreamID && self.subtitleStreamID.integerValue != 0;
    if (currentlyOn) {
        self.subtitleStreamID = @0;
    } else {
        if (!self.lastNonZeroSubtitleStreamID) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sin subtitulos"
                message:@"Este video no tiene ninguna pista de subtitulos incrustada."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        self.subtitleStreamID = self.lastNonZeroSubtitleStreamID;
    }
    self.subtitlesButton.alpha = [self subtitlesButtonVisibleAlpha];
    NSInteger current = [self currentAbsoluteSeconds];
    [self stopCurrentSessionAndStartNewOneWithSubtitleChangeAtOffsetSeconds:current];
    [self scheduleAutoHide];
}

// Opens the full subtitle picker (existing tracks + search/download online) that the
// detail screen already uses, so the gear icon has a real function instead of a stub.
- (void)settingsTapped {
    [self.autoHideTimer invalidate];
    SubtitlePickerViewController *picker = [[SubtitlePickerViewController alloc] init];
    picker.ratingKey = self.item[@"ratingKey"];
    picker.existingStreams = self.subtitleStreams;
    picker.selectedStreamID = self.subtitleStreamID ?: @0;
    __weak typeof(self) weakSelf = self;
    picker.onSelect = ^(NSNumber *streamID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.subtitleStreamID = streamID;
        strongSelf.lastNonZeroSubtitleStreamID = (streamID.integerValue != 0) ? streamID : strongSelf.lastNonZeroSubtitleStreamID;
        strongSelf.subtitlesButton.alpha = [strongSelf subtitlesButtonVisibleAlpha];
        NSInteger current = [strongSelf currentAbsoluteSeconds];
        [strongSelf stopCurrentSessionAndStartNewOneWithSubtitleChangeAtOffsetSeconds:current];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

// UISlider draws its default thumb tiny and hard to see on video; a small solid
// circle image reads much better and matches the accent color used elsewhere.
// Small solid dot, like YouTube's scrub handle - only meant to be visible/draggable,
// not a decorative element.
- (UIImage *)sliderThumbImage {
    CGFloat side = 11;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, side, side));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.playerLayer.frame = b;
    self.spinner.center = CGPointMake(b.size.width / 2.0, b.size.height / 2.0);
    CGFloat pad = 20;

    // --- top bar: title + meta line on the left, close "X" on the right ---
    CGFloat topH = 96;
    self.topBar.frame = CGRectMake(0, 0, b.size.width, topH);
    self.topGradient.frame = self.topBar.bounds;
    self.closeButton.frame = CGRectMake(b.size.width - pad - 44, 24, 44, 44);
    CGFloat titleW = self.closeButton.frame.origin.x - pad - 12;
    self.titleLabel.frame = CGRectMake(pad, 24, titleW, 30);
    self.metaLabel.frame = CGRectMake(pad, CGRectGetMaxY(self.titleLabel.frame) + 2, titleW, 18);

    // --- center transport: three circular buttons, sized from their own diameters ---
    CGFloat playD = self.playPauseButton.frame.size.width ?: 74;
    CGFloat skipD = self.skipBackButton.frame.size.width ?: 52;
    CGFloat gap = 30;
    CGFloat rowH = MAX(playD, skipD);
    CGFloat totalW = skipD + gap + playD + gap + skipD;
    CGFloat startX = (b.size.width - totalW) / 2.0;
    CGFloat rowY = b.size.height / 2.0 - rowH / 2.0;

    self.centerControls.frame = CGRectMake(0, rowY, b.size.width, rowH);
    self.skipBackButton.frame = CGRectMake(startX, (rowH - skipD) / 2.0, skipD, skipD);
    self.playPauseButton.frame = CGRectMake(startX + skipD + gap, (rowH - playD) / 2.0, playD, playD);
    self.skipForwardButton.frame = CGRectMake(startX + skipD + gap + playD + gap, (rowH - skipD) / 2.0, skipD, skipD);

    // --- icon row above the scrub bar (subtitles + settings, right-aligned) ---
    CGFloat iconRowY = b.size.height - 46 - 40;
    self.settingsButton.frame = CGRectMake(b.size.width - pad - 32, iconRowY, 32, 32);
    self.subtitlesButton.frame = CGRectMake(self.settingsButton.frame.origin.x - 12 - 32, iconRowY, 32, 32);

    // --- bottom scrub bar: the *visual* track is thin, but the slider's frame (its actual
    // draggable hit area) is a generous 44pt tall. A too-thin touch target was why a slightly
    // diagonal drag could slip outside the slider's bounds mid-gesture and release early at
    // the wrong position - UISlider only draws a thin bar regardless of how tall its frame is,
    // so this fixes the "lands at a random point" seek bug without changing the look.
    CGFloat bottomH = 60;
    self.bottomBar.frame = CGRectMake(0, b.size.height - bottomH, b.size.width, bottomH);
    self.bottomGradient.frame = self.bottomBar.bounds;
    self.elapsedLabel.frame = CGRectMake(pad, 30, 50, 16);
    self.remainingLabel.frame = CGRectMake(b.size.width - pad - 50, 30, 50, 16);
    CGFloat sliderX = CGRectGetMaxX(self.elapsedLabel.frame) + 8;
    CGFloat sliderW = self.remainingLabel.frame.origin.x - 8 - sliderX;
    self.slider.frame = CGRectMake(sliderX, 8, sliderW, 44);
}

- (NSString *)formatSeconds:(NSInteger)total {
    // Avoid the "%" operator: this old armv7s toolchain has no __modsi3 in its runtime.
    NSInteger minutes = total / 60;
    NSInteger seconds = total - (minutes * 60);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
}

// Confirmed via on-screen diagnostics (base=953, player.currentTime=966): Plex's HLS output
// for an offset-based transcode keeps the ORIGINAL video's absolute position in the segment
// timestamps, so AVPlayer's own currentTime already IS the absolute position - not time
// elapsed since this transcode session started. Adding baseOffsetSeconds on top of it was
// counting the same position twice (953 + 966 = 1919, exactly the reported "x2" bug). This
// is now the single source of truth for "where are we" - never add baseOffsetSeconds to it.
- (NSInteger)currentAbsoluteSeconds {
    return (NSInteger)CMTimeGetSeconds(self.player.currentTime);
}

#pragma mark Playback pipeline

// Confirmed via the server log: passing "subtitleStreamID" on the transcode session URL is
// simply ignored - Plex auto-selects a subtitle by its own account/language logic no matter
// what that param says (it kept resolving to the same stream regardless of what was
// requested). What auto-select actually honors is the file's *persisted default* subtitle
// stream (PUT /library/parts/{id}?subtitleStreamID=X), so that has to be set first, and only
// then does starting a fresh transcode session (a reused session ignores the change too) pick
// it up.
- (void)stopCurrentSessionAndStartNewOneWithSubtitleChangeAtOffsetSeconds:(NSInteger)offset {
    NSString *oldSessionId = self.sessionId;
    if (oldSessionId) {
        NSString *stopStr = [NSString stringWithFormat:@"%@/video/:/transcode/universal/stop?session=%@", PLEX_SERVER, PlexURLEncode(oldSessionId)];
        [PlexClient getJSON:[NSURL URLWithString:stopStr] completion:^(id json, NSError *error) {}];
    }
    self.sessionId = [[NSUUID UUID] UUIDString];

    NSNumber *streamID = self.subtitleStreamID ?: @0;
    if (self.partId) {
        __weak typeof(self) weakSelf = self;
        [PlexClient setDefaultSubtitleStreamID:streamID forPartID:self.partId completion:^(BOOL ok) {
            [weakSelf startAtOffsetSeconds:offset];
        }];
    } else {
        // No part id yet (loadSubtitleStreams hasn't finished) - proceed anyway rather than
        // getting stuck; the subtitle just won't switch this one time.
        [self startAtOffsetSeconds:offset];
    }
}

- (void)startAtOffsetSeconds:(NSInteger)offset {
    // Detach the old item's time observer *synchronously*, right now - not later inside
    // attachPlayerItemWithURL. Otherwise, while we wait for the decision/start network
    // round trip, the still-playing old item keeps firing its observer, computing a bogus
    // position that yanks the slider away from where the user just dropped it. Pausing the
    // old item too avoids a confusing moment of stale audio/video.
    [self removeTimeObserver];
    [self.player pause];

    self.slider.value = offset;
    self.elapsedLabel.text = [self formatSeconds:offset];
    self.remainingLabel.text = [NSString stringWithFormat:@"-%@", [self formatSeconds:MAX(0, self.durationSeconds - offset)]];
    [self.spinner startAnimating];

    // Two consecutive drags/taps (e.g. the user overshoots and immediately corrects) fire
    // two independent async request pairs; network responses can arrive out of order, so
    // whichever happened to finish LAST used to win even if it was requested FIRST. Tag
    // every seek with an incrementing generation and only act on it if it is still current.
    self.seekGeneration += 1;
    NSInteger myGeneration = self.seekGeneration;

    NSURL *decisionURL = [PlexPlayback universalTranscodeURLForItem:self.item endpoint:@"decision" sessionId:self.sessionId subtitleStreamID:self.subtitleStreamID offsetSeconds:offset];
    NSURL *startURL = [PlexPlayback universalTranscodeURLForItem:self.item endpoint:@"start.m3u8" sessionId:self.sessionId subtitleStreamID:self.subtitleStreamID offsetSeconds:offset];

    __weak typeof(self) weakSelf = self;
    [PlexClient getJSON:decisionURL completion:^(id json, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.seekGeneration != myGeneration) return; // superseded by a newer seek
        [strongSelf attachPlayerItemWithURL:startURL generation:myGeneration];
    }];
}

- (void)attachPlayerItemWithURL:(NSURL *)url generation:(NSInteger)generation {
    if (self.seekGeneration != generation) return; // superseded by a newer seek while start.m3u8 was building
    if (!url) {
        [self failWithMessage:@"No se pudo construir la URL de reproduccion."];
        return;
    }
    AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:url];

    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:newItem];
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        self.playerLayer.frame = self.view.bounds;
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [self.view.layer insertSublayer:self.playerLayer atIndex:0];
        [self startCleanupWatchdog];
        [self addTimeObserver];
    } else {
        [self removeTimeObserver];
        [self.player replaceCurrentItemWithPlayerItem:newItem];
        [self addTimeObserver];
    }

    // Every previous item's failure observer must go, or an *old, already-abandoned* item
    // that errors out later (which is normal - we just cut its connection) fires this and
    // kills the whole player even though the newer seek/toggle already succeeded. That was
    // the actual cause behind seeking "never working": the seek itself was fine, a stale
    // notification from the item it replaced took the player down a moment later.
    if (self.failureObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.failureObserver];
        self.failureObserver = nil;
    }

    __weak typeof(self) weakSelf = self;
    self.failureObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
        object:newItem queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.seekGeneration != generation) return; // stale item, ignore
            NSError *err = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
            [strongSelf failWithMessage:[NSString stringWithFormat:@"Fallo durante transcodificacion.\n\n%@", err.localizedDescription ?: @""]];
        }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.seekGeneration != generation) return; // superseded since
        if (newItem.status == AVPlayerItemStatusFailed) {
            [strongSelf failWithMessage:[NSString stringWithFormat:@"No se pudo iniciar la reproduccion.\n\n%@", newItem.error.localizedDescription ?: @""]];
            return;
        }
        [strongSelf.spinner stopAnimating];
        [strongSelf.player play];
        [strongSelf.playPauseButton setImage:PlexIconImage(PlexIconPause, 30) forState:UIControlStateNormal];
        [strongSelf scheduleAutoHide];
    });
}

- (void)addTimeObserver {
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isScrubbing) return;
        NSInteger absolute = (NSInteger)CMTimeGetSeconds(time); // this already IS the absolute position, see currentAbsoluteSeconds
        strongSelf.slider.value = absolute;
        strongSelf.elapsedLabel.text = [strongSelf formatSeconds:absolute];
        strongSelf.remainingLabel.text = [NSString stringWithFormat:@"-%@", [strongSelf formatSeconds:MAX(0, strongSelf.durationSeconds - absolute)]];
        // Do NOT tie the spinner's visibility to player.rate here: rate is also 0 when
        // the user has deliberately paused, not just while buffering. That previously
        // made the spinner reappear over the play button every time you paused, and
        // since it still had user interaction enabled it silently ate the next tap -
        // "impossible to resume". The spinner's own start/stopAnimating calls (which
        // auto-hide it) already track the real loading state correctly on their own.
    }];
}

- (void)removeTimeObserver {
    if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
    self.timeObserver = nil;
}

- (void)startCleanupWatchdog {
    __weak typeof(self) weakSelf = self;
    self.cleanupPoll = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        if (weakSelf.view.window == nil) {
            [timer invalidate];
            NSString *stopStr = [NSString stringWithFormat:@"%@/video/:/transcode/universal/stop?session=%@", PLEX_SERVER, PlexURLEncode(weakSelf.sessionId)];
            [PlexClient getJSON:[NSURL URLWithString:stopStr] completion:^(id json, NSError *error) {}];
        }
    }];
}

- (void)failWithMessage:(NSString *)message {
    [self.spinner stopAnimating];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No se pudo reproducir"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf closeTapped];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Controls

- (void)playPauseTapped {
    if (self.player.rate == 0) {
        [self.player play];
        [self.playPauseButton setImage:PlexIconImage(PlexIconPause, 30) forState:UIControlStateNormal];
    } else {
        [self.player pause];
        [self.playPauseButton setImage:PlexIconImage(PlexIconPlay, 30) forState:UIControlStateNormal];
    }
    [self scheduleAutoHide];
}

- (void)skipBackTapped {
    NSInteger current = [self currentAbsoluteSeconds];
    [self startAtOffsetSeconds:MAX(0, current - 10)];
    [self scheduleAutoHide];
}

- (void)skipForwardTapped {
    NSInteger current = [self currentAbsoluteSeconds];
    [self startAtOffsetSeconds:MIN(self.durationSeconds, current + 10)];
    [self scheduleAutoHide];
}

- (void)sliderTouchDown {
    self.isScrubbing = YES;
    [self.autoHideTimer invalidate];
}

- (void)sliderChanged {
    NSInteger v = (NSInteger)self.slider.value;
    self.elapsedLabel.text = [self formatSeconds:v];
    self.remainingLabel.text = [NSString stringWithFormat:@"-%@", [self formatSeconds:MAX(0, self.durationSeconds - v)]];
}

- (void)sliderTouchUp {
    self.isScrubbing = NO;
    NSInteger target = (NSInteger)self.slider.value;
    [self startAtOffsetSeconds:target];
    [self scheduleAutoHide];
}

- (void)closeTapped {
    self.seekGeneration += 1; // invalidate any seek still in flight so it can't reopen anything after we leave
    [self removeTimeObserver];
    if (self.failureObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.failureObserver];
        self.failureObserver = nil;
    }
    [self.cleanupPoll invalidate];
    [self.autoHideTimer invalidate];
    NSString *stopStr = [NSString stringWithFormat:@"%@/video/:/transcode/universal/stop?session=%@", PLEX_SERVER, PlexURLEncode(self.sessionId)];
    [PlexClient getJSON:[NSURL URLWithString:stopStr] completion:^(id json, NSError *error) {}];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc {
    if (self.failureObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.failureObserver];
    }
}

#pragma mark Show/hide controls

// Only let the background tap gesture consider taps on genuinely empty video area - never
// on a button or the slider, so it can never race with or double-fire alongside them.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

- (void)videoTapped {
    BOOL currentlyHidden = self.topBar.alpha < 0.5;
    [self setControlsHidden:!currentlyHidden];
    if (currentlyHidden) [self scheduleAutoHide];
    else [self.autoHideTimer invalidate];
}

// The subtitles/settings buttons live directly on the view rather than inside topBar or
// bottomBar, so they have to be faded explicitly here too - otherwise they stayed on screen
// after everything else had hidden itself.
- (void)setControlsHidden:(BOOL)hidden {
    [UIView animateWithDuration:0.2 animations:^{
        CGFloat alpha = hidden ? 0.0 : 1.0;
        self.topBar.alpha = alpha;
        self.centerControls.alpha = alpha;
        self.bottomBar.alpha = alpha;
        self.settingsButton.alpha = alpha;
        // Subtitles button carries its own on/off meaning in its alpha, so restore that
        // state rather than a flat 1.0 when the controls come back.
        self.subtitlesButton.alpha = hidden ? 0.0 : [self subtitlesButtonVisibleAlpha];
    }];
}

- (CGFloat)subtitlesButtonVisibleAlpha {
    return (self.subtitleStreamID && self.subtitleStreamID.integerValue != 0) ? 1.0 : 0.4;
}

- (void)scheduleAutoHide {
    [self.autoHideTimer invalidate];
    if (self.player.rate == 0) return; // don't hide controls while paused
    __weak typeof(self) weakSelf = self;
    self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:4.0 repeats:NO block:^(NSTimer *timer) {
        [weakSelf setControlsHidden:YES];
    }];
}

@end

#pragma mark - Subtitle search results

@implementation SubtitleSearchResultsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Resultados";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *r = self.results[indexPath.row];
    cell.textLabel.text = r[@"title"] ?: r[@"displayTitle"] ?: r[@"key"] ?: @"(sin nombre)";
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.text = r[@"languageCode"] ?: r[@"language"] ?: @"";
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *r = self.results[indexPath.row];
    NSString *key = r[@"key"];
    if (![key isKindOfClass:[NSString class]]) return;

    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spin.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    [spin startAnimating];
    [self.view addSubview:spin];

    __weak typeof(self) weakSelf = self;
    [PlexClient downloadSubtitleForRatingKey:self.ratingKey key:key completion:^(BOOL ok) {
        [spin removeFromSuperview];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:ok ? @"Descargando" : @"Error"
            message:ok ? @"El subtitulo se esta descargando en el servidor. Vuelve a abrir el selector de subtitulos en unos segundos para elegirlo." : @"No se pudo descargar el subtitulo."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (ok && weakSelf.onDownloaded) weakSelf.onDownloaded();
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    }];
}

@end

#pragma mark - Subtitle picker

@implementation SubtitlePickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Subtitulos";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    if (!self.selectedStreamID) self.selectedStreamID = @0;

    // When pushed onto an existing stack (from the detail screen) this replaces the
    // automatic back button, which still just pops - no functional loss. When presented
    // as the root of its own modal navigation controller (from the player's settings
    // button) there was otherwise NO way to leave this screen at all.
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cerrar"
        style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
}

- (void)closeTapped {
    if (self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (1 + self.existingStreams.count) : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"En este archivo" : @"Buscar en linea";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Ninguno";
            if (self.selectedStreamID.integerValue == 0) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            NSDictionary *s = self.existingStreams[indexPath.row - 1];
            cell.textLabel.text = s[@"extendedDisplayTitle"] ?: s[@"displayTitle"] ?: s[@"language"] ?: @"Subtitulo";
            NSNumber *sid = s[@"id"];
            if (sid && [self.selectedStreamID isEqual:sid]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    } else {
        cell.textLabel.text = indexPath.row == 0 ? @"Buscar en espanol" : @"Buscar en ingles";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSNumber *sid = indexPath.row == 0 ? @0 : self.existingStreams[indexPath.row - 1][@"id"];
        self.selectedStreamID = sid ?: @0;
        if (self.onSelect) self.onSelect(self.selectedStreamID);
        [self.tableView reloadData];
        return;
    }

    NSString *lang = indexPath.row == 0 ? @"es" : @"en";
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spin.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    [spin startAnimating];
    [self.view addSubview:spin];

    __weak typeof(self) weakSelf = self;
    [PlexClient searchSubtitlesForRatingKey:self.ratingKey language:lang completion:^(NSArray *results, NSError *error) {
        [spin removeFromSuperview];
        if (error || results.count == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sin resultados"
                message:error ? error.localizedDescription : @"No se encontraron subtitulos para ese idioma (puede que el servidor no tenga un proveedor de subtitulos configurado)."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        SubtitleSearchResultsViewController *resultsVC = [[SubtitleSearchResultsViewController alloc] init];
        resultsVC.ratingKey = weakSelf.ratingKey;
        resultsVC.results = results;
        [weakSelf.navigationController pushViewController:resultsVC animated:YES];
    }];
}

@end

#pragma mark - Detail screen (poster, summary, play + subtitles)

@implementation PlexDetailViewController

- (UILabel *)makeLabelSize:(CGFloat)size bold:(BOOL)bold {
    UILabel *l = [[UILabel alloc] init];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = [UIColor whiteColor];
    return l;
}

- (UIButton *)makeButtonTitle:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.layer.cornerRadius = 8;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.backdrop = [[UIImageView alloc] init];
    self.backdrop.contentMode = UIViewContentModeScaleAspectFill;
    self.backdrop.clipsToBounds = YES;
    self.backdrop.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    [self.view addSubview:self.backdrop];

    UIView *scrim = [[UIView alloc] init];
    scrim.tag = 501;
    scrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    [self.backdrop addSubview:scrim];

    self.titleLabel = [self makeLabelSize:26 bold:YES];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.text = self.item[@"title"];
    [self.view addSubview:self.titleLabel];

    self.infoLabel = [self makeLabelSize:15 bold:NO];
    self.infoLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1];
    [self.view addSubview:self.infoLabel];

    self.summaryView = [[UITextView alloc] init];
    self.summaryView.backgroundColor = [UIColor clearColor];
    self.summaryView.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.summaryView.font = [UIFont systemFontOfSize:15];
    self.summaryView.editable = NO;
    self.summaryView.text = self.item[@"summary"] ?: @"";
    [self.view addSubview:self.summaryView];

    self.playButton = [self makeButtonTitle:@"Reproducir" color:[UIColor colorWithRed:0.90 green:0.65 blue:0.13 alpha:1]];
    [self.playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playButton];

    self.subsButton = [self makeButtonTitle:@"Subtitulos: Ninguno" color:[UIColor colorWithWhite:0.2 alpha:1]];
    [self.subsButton addTarget:self action:@selector(subsTapped) forControlEvents:UIControlEventTouchUpInside];
    self.subsButton.enabled = NO;
    [self.view addSubview:self.subsButton];

    NSString *type = self.item[@"type"];
    if ([type isEqualToString:@"episode"]) {
        self.infoLabel.text = [NSString stringWithFormat:@"Temporada %@ - Episodio %@", self.item[@"parentIndex"] ?: @0, self.item[@"index"] ?: @0];
    } else {
        id year = self.item[@"year"];
        self.infoLabel.text = year ? [NSString stringWithFormat:@"%@", year] : @"";
    }

    NSString *art = self.item[@"art"] ?: self.item[@"thumb"];
    [PlexClient loadImage:[PlexClient imageURLForThumb:art] completion:^(UIImage *img) {
        self.backdrop.image = img;
    }];

    [self loadDetail];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.backdrop.frame = CGRectMake(0, 0, b.size.width, b.size.height * 0.4);
    UIView *scrim = [self.backdrop viewWithTag:501];
    scrim.frame = self.backdrop.bounds;

    CGFloat pad = 24;
    CGFloat y = CGRectGetMaxY(self.backdrop.frame) + 16;
    self.titleLabel.frame = CGRectMake(pad, y, b.size.width - pad * 2, 66);
    y = CGRectGetMaxY(self.titleLabel.frame) + 2;
    self.infoLabel.frame = CGRectMake(pad, y, b.size.width - pad * 2, 20);
    y = CGRectGetMaxY(self.infoLabel.frame) + 10;

    CGFloat buttonsY = b.size.height - 76;
    self.summaryView.frame = CGRectMake(pad - 4, y, b.size.width - (pad - 4) * 2, MAX(40, buttonsY - y - 12));

    CGFloat btnW = (b.size.width - pad * 2 - 16) / 2.0;
    self.playButton.frame = CGRectMake(pad, buttonsY, btnW, 50);
    self.subsButton.frame = CGRectMake(pad + btnW + 16, buttonsY, btnW, 50);
}

- (NSArray *)subtitleStreamsFromItem:(NSDictionary *)full {
    NSArray *media = full[@"Media"];
    if (![media isKindOfClass:[NSArray class]] || media.count == 0) return @[];
    NSArray *parts = media[0][@"Part"];
    if (![parts isKindOfClass:[NSArray class]] || parts.count == 0) return @[];
    NSArray *streams = parts[0][@"Stream"];
    if (![streams isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *subs = [NSMutableArray array];
    for (NSDictionary *s in streams) {
        if ([s[@"streamType"] integerValue] == 3) [subs addObject:s];
    }
    return subs;
}

- (void)loadDetail {
    NSString *ratingKey = self.item[@"ratingKey"];
    __weak typeof(self) weakSelf = self;
    [PlexClient fetchDetail:[NSString stringWithFormat:@"%@", ratingKey] completion:^(NSDictionary *full) {
        weakSelf.fullItem = full ?: weakSelf.item;
        NSArray *media = weakSelf.fullItem[@"Media"];
        NSArray *parts = [media isKindOfClass:[NSArray class]] && media.count > 0 ? media[0][@"Part"] : nil;
        weakSelf.partId = ([parts isKindOfClass:[NSArray class]] && parts.count > 0) ? parts[0][@"id"] : nil;
        weakSelf.subsButton.enabled = YES;
        [weakSelf updateSubsButtonTitle];
    }];
}

- (void)updateSubsButtonTitle {
    NSString *title = @"Subtitulos: Ninguno";
    NSNumber *selected = self.selectedSubtitleStreamID;
    if (selected && selected.integerValue != 0) {
        for (NSDictionary *s in [self subtitleStreamsFromItem:self.fullItem]) {
            if ([s[@"id"] isEqual:selected]) {
                title = [NSString stringWithFormat:@"Subtitulos: %@", s[@"extendedDisplayTitle"] ?: s[@"language"] ?: @"activo"];
                break;
            }
        }
    }
    [self.subsButton setTitle:title forState:UIControlStateNormal];
}

- (void)playTapped {
    [PlexPlayback playItem:self.item subtitleStreamID:self.selectedSubtitleStreamID fromViewController:self];
}

- (void)subsTapped {
    if (!self.fullItem) return;
    SubtitlePickerViewController *picker = [[SubtitlePickerViewController alloc] init];
    picker.ratingKey = self.item[@"ratingKey"];
    picker.existingStreams = [self subtitleStreamsFromItem:self.fullItem];
    picker.selectedStreamID = self.selectedSubtitleStreamID ?: @0;
    __weak typeof(self) weakSelf = self;
    picker.onSelect = ^(NSNumber *streamID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.selectedSubtitleStreamID = streamID;
        [strongSelf updateSubsButtonTitle];
        // Same fix as the in-player toggle: the transcode session's own subtitleStreamID
        // param is ignored by Plex's auto-select, so the file's persisted default has to be
        // set here too, before playback even starts, or picking one here would silently do
        // nothing once "Reproducir" is tapped.
        if (strongSelf.partId) {
            [PlexClient setDefaultSubtitleStreamID:streamID forPartID:strongSelf.partId completion:^(BOOL ok) {}];
        }
    };
    [self.navigationController pushViewController:picker animated:YES];
}

@end

#pragma mark - App Delegate

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    if ([PlexClient authToken]) {
        [self showLibraries];
    } else {
        LinkViewController *link = [[LinkViewController alloc] init];
        __weak typeof(self) weakSelf = self;
        link.onLinked = ^{
            [weakSelf showLibraries];
        };
        self.window.rootViewController = link;
    }

    [self.window makeKeyAndVisible];
    return YES;
}

- (void)showLibraries {
    PlexListViewController *root = [[PlexListViewController alloc] init];
    root.title = @"Plex";
    root.fetchPath = @"/library/sections";
    root.isTopLevel = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    self.window.rootViewController = nav;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
