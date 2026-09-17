#import <UIKit/UIKit.h>

@interface LinkViewController : UIViewController
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, copy) void (^onLinked)(void);
@end
