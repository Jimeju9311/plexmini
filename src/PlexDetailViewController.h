#import <UIKit/UIKit.h>

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
