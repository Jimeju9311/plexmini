#import <UIKit/UIKit.h>

UIColor *PlexAccentColor(void);

// Hand-drawn vector icons - never unicode symbol glyphs, which render as
// full-color emoji on Apple platforms (e.g. "⏸").
typedef NS_ENUM(NSInteger, PlexIconKind) {
    PlexIconPlay,
    PlexIconPause,
    PlexIconClose,
    PlexIconSubtitles,
    PlexIconSettings
};

UIImage *PlexIconImage(PlexIconKind kind, CGFloat size);
UIButton *PlexIconButton(PlexIconKind kind, CGFloat size);
UIButton *PlexCircleIconButton(PlexIconKind kind, CGFloat iconSize, CGFloat diameter);
UIButton *PlexCircleTextButton(NSString *text, CGFloat fontSize, CGFloat diameter);
