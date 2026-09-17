#import <UIKit/UIKit.h>

@interface SubtitlePickerViewController : UITableViewController
@property (nonatomic, copy) NSString *ratingKey;
@property (nonatomic, copy) NSArray *existingStreams; // Stream dicts with streamType == 3
@property (nonatomic, strong) NSNumber *selectedStreamID; // @0 = none, @(id) = a specific stream
@property (nonatomic, copy) void (^onSelect)(NSNumber *streamID);
@end
