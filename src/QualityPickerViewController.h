#import <UIKit/UIKit.h>

// Picks the transcode quality. Changing it needs a brand new transcode session, so the
// caller has to restart playback at the current position - same as a subtitle change.
@interface QualityPickerViewController : UITableViewController
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
@end
