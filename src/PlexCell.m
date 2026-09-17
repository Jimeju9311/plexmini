#import "PlexCell.h"

@implementation PlexCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        self.textLabel.textColor = [UIColor whiteColor];
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.clipsToBounds = YES;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        self.selectedBackgroundView = bg;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = self.contentView.bounds.size.height - 8;
    self.imageView.frame = CGRectMake(8, 4, side * 0.68, side);
    CGFloat textX = CGRectGetMaxX(self.imageView.frame) + 12;
    self.textLabel.frame = CGRectMake(textX, self.textLabel.frame.origin.y, self.contentView.bounds.size.width - textX - 30, self.textLabel.frame.size.height);
    self.detailTextLabel.frame = CGRectMake(textX, self.detailTextLabel.frame.origin.y, self.contentView.bounds.size.width - textX - 30, self.detailTextLabel.frame.size.height);
}

@end
