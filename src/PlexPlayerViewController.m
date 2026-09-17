#import "PlexPlayerViewController.h"
#import "PlexClient.h"
#import "PlexConfig.h"
#import "PlexPlayback.h"
#import "PlexTheme.h"
#import "SubtitlePickerViewController.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

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
