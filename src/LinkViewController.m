#import "LinkViewController.h"
#import "PlexClient.h"

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
