#import <UIKit/UIKit.h>

// The player's gear menu. It used to open the subtitle picker directly; now that there
// is more than one thing to configure, it lists them and pushes the right picker.
@interface PlayerSettingsViewController : UITableViewController

// Passed straight through to the subtitle picker.
@property (nonatomic, copy) NSString *ratingKey;
@property (nonatomic, copy) NSArray *subtitleStreams;
@property (nonatomic, strong) NSNumber *selectedSubtitleStreamID;

@property (nonatomic, copy) void (^onSelectSubtitle)(NSNumber *streamID);
@property (nonatomic, copy) void (^onChangeQuality)(void);

@end
