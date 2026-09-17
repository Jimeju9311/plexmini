#import <UIKit/UIKit.h>

@interface PlexListViewController : UITableViewController
@property (nonatomic, copy) NSString *fetchPath;   // e.g. /library/sections  or /library/sections/1/all
@property (nonatomic, copy) NSArray *items;         // array of NSDictionary (Directory/Video entries)
@property (nonatomic, assign) BOOL isTopLevel;      // YES only for the root /library/sections screen
@end
