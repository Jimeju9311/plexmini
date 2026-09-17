#import "PlexDetailViewController.h"
#import "PlexClient.h"
#import "PlexPlayback.h"
#import "SubtitlePickerViewController.h"

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
