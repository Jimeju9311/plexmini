#import <UIKit/UIKit.h>

@interface SubtitleSearchResultsViewController : UITableViewController
@property (nonatomic, copy) NSString *ratingKey;
@property (nonatomic, copy) NSArray *results;
@property (nonatomic, copy) void (^onDownloaded)(void);
@end
