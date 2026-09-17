#import "PlexTheme.h"

UIColor *PlexAccentColor(void) {
    return [UIColor colorWithRed:0.90 green:0.65 blue:0.13 alpha:1];
}

UIImage *PlexIconImage(PlexIconKind kind, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextSetStrokeColorWithColor(ctx, [UIColor whiteColor].CGColor);

    switch (kind) {
        case PlexIconPlay: {
            CGFloat inset = size * 0.28;
            UIBezierPath *tri = [UIBezierPath bezierPath];
            [tri moveToPoint:CGPointMake(inset, size * 0.18)];
            [tri addLineToPoint:CGPointMake(inset, size * 0.82)];
            [tri addLineToPoint:CGPointMake(size - inset * 0.7, size * 0.5)];
            [tri closePath];
            [tri fill];
            break;
        }
        case PlexIconPause: {
            CGFloat barW = size * 0.16;
            CGFloat gap = size * 0.16;
            CGFloat barH = size * 0.6;
            CGFloat y = (size - barH) / 2.0;
            CGFloat totalW = barW * 2 + gap;
            CGFloat startX = (size - totalW) / 2.0;
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(startX, y, barW, barH) cornerRadius:barW * 0.25] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(startX + barW + gap, y, barW, barH) cornerRadius:barW * 0.25] fill];
            break;
        }
        case PlexIconClose: {
            CGContextSetLineWidth(ctx, size * 0.09);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGFloat m = size * 0.28;
            CGContextMoveToPoint(ctx, m, m);
            CGContextAddLineToPoint(ctx, size - m, size - m);
            CGContextMoveToPoint(ctx, size - m, m);
            CGContextAddLineToPoint(ctx, m, size - m);
            CGContextStrokePath(ctx);
            break;
        }
        case PlexIconSubtitles: {
            CGFloat inset = size * 0.10;
            UIBezierPath *box = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(inset, size * 0.22, size - inset * 2, size * 0.56) cornerRadius:size * 0.08];
            box.lineWidth = size * 0.08;
            [[UIColor whiteColor] setStroke];
            [box stroke];
            CGFloat lineY1 = size * 0.40, lineY2 = size * 0.58;
            CGContextSetLineWidth(ctx, size * 0.07);
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGContextMoveToPoint(ctx, size * 0.24, lineY1);
            CGContextAddLineToPoint(ctx, size * 0.50, lineY1);
            CGContextMoveToPoint(ctx, size * 0.24, lineY2);
            CGContextAddLineToPoint(ctx, size * 0.70, lineY2);
            CGContextStrokePath(ctx);
            break;
        }
        case PlexIconSettings: {
            CGPoint center = CGPointMake(size / 2.0, size / 2.0);
            CGFloat outerR = size * 0.42;
            CGFloat innerR = size * 0.22;
            CGFloat toothW = size * 0.16;
            CGFloat toothH = size * 0.14;
            NSInteger teeth = 8;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, center.x, center.y);
            for (NSInteger i = 0; i < teeth; i++) {
                CGContextFillRect(ctx, CGRectMake(-toothW / 2.0, -outerR - toothH / 2.0, toothW, toothH));
                CGContextRotateCTM(ctx, 2.0 * M_PI / teeth);
            }
            CGContextRestoreGState(ctx);
            UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:center radius:(outerR + innerR) / 2.0
                startAngle:0 endAngle:2 * M_PI clockwise:YES];
            ring.lineWidth = outerR - innerR;
            [[UIColor whiteColor] setStroke];
            [ring stroke];
            break;
        }
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

UIButton *PlexIconButton(PlexIconKind kind, CGFloat size) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:PlexIconImage(kind, size) forState:UIControlStateNormal];
    b.backgroundColor = [UIColor clearColor];
    return b;
}

// Circular translucent buttons matching the reference layout's transport controls
// (skip-back/play-pause/skip-forward sit on a dark circular disc in real Plex).
UIButton *PlexCircleIconButton(PlexIconKind kind, CGFloat iconSize, CGFloat diameter) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:PlexIconImage(kind, iconSize) forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.75];
    b.layer.cornerRadius = diameter / 2.0;
    return b;
}

UIButton *PlexCircleTextButton(NSString *text, CGFloat fontSize, CGFloat diameter) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.75];
    b.layer.cornerRadius = diameter / 2.0;
    return b;
}
