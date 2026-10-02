#import "SVTimelineView.h"

UIColor *SVColorOn(void)      { return [UIColor colorWithRed:0.98 green:0.78 blue:0.16 alpha:1]; }
UIColor *SVColorOff(void)     { return [UIColor colorWithRed:0.27 green:0.29 blue:0.33 alpha:1]; }
UIColor *SVColorMaybe(void)   { return [UIColor colorWithRed:0.93 green:0.50 blue:0.18 alpha:1]; }
UIColor *SVColorUnknown(void) { return [UIColor colorWithWhite:0.86 alpha:1]; }

static const CGFloat kBarH = 26.0;
static const CGFloat kLabelH = 14.0;
static const CGFloat kRowGap = 8.0;
static const CGFloat kPad = 10.0;

@implementation SVTimelineView

@synthesize slots = _slots, nowSlot = _nowSlot, nowFraction = _nowFraction;

+ (CGFloat)preferredHeight {
    return kPad * 2 + (kBarH + kLabelH) * 2 + kRowGap;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        _nowSlot = -1;
    }
    return self;
}

- (void)dealloc {
    [_slots release];
    [super dealloc];
}

- (void)setSlots:(NSString *)s { if (s != _slots) { [_slots release]; _slots = [s copy]; [self setNeedsDisplay]; } }
- (void)setNowSlot:(NSInteger)n { _nowSlot = n; [self setNeedsDisplay]; }

- (UIColor *)colorFor:(unichar)c {
    switch (c) {
        case '0': return SVColorOn();
        case '1': return SVColorOff();
        case '2': return SVColorMaybe();
        default:  return SVColorUnknown();
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width - kPad * 2;
    CGFloat cell = w / 24.0;
    UIFont *font = [UIFont systemFontOfSize:10];

    for (NSInteger row = 0; row < 2; row++) {
        CGFloat y = kPad + row * (kBarH + kLabelH + kRowGap);
        CGRect bar = CGRectMake(kPad, y, w, kBarH);

        // rounded clip for the bar
        CGContextSaveGState(ctx);
        UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:5];
        [clip addClip];

        for (NSInteger i = 0; i < 24; i++) {
            NSInteger idx = row * 24 + i;
            unichar c = (_slots.length == 48) ? [_slots characterAtIndex:idx] : '?';
            CGRect r = CGRectMake(kPad + i * cell, y, cell + 0.5, kBarH);
            [[self colorFor:c] setFill];
            UIRectFill(r);
            if (c == '2') {
                // diagonal hatching for "possible"
                CGContextSaveGState(ctx);
                CGContextClipToRect(ctx, r);
                [[UIColor colorWithWhite:1 alpha:0.35] setStroke];
                CGContextSetLineWidth(ctx, 2);
                for (CGFloat x = r.origin.x - kBarH; x < CGRectGetMaxX(r); x += 6) {
                    CGContextMoveToPoint(ctx, x, CGRectGetMaxY(r));
                    CGContextAddLineToPoint(ctx, x + kBarH, r.origin.y);
                }
                CGContextStrokePath(ctx);
                CGContextRestoreGState(ctx);
            }
        }

        // glossy top highlight (iOS 6 feel)
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[] = { 1, 1, 1, 0.35,   1, 1, 1, 0.0 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
        CGContextDrawLinearGradient(ctx, g, CGPointMake(0, y), CGPointMake(0, y + kBarH / 2), 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);

        // hour separators
        [[UIColor colorWithWhite:1 alpha:0.55] setFill];
        for (NSInteger h = 1; h < 12; h++) {
            UIRectFill(CGRectMake(kPad + h * 2 * cell - 0.5, y, 1, kBarH));
        }
        CGContextRestoreGState(ctx);

        // border
        [[UIColor colorWithWhite:0 alpha:0.25] setStroke];
        UIBezierPath *border = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bar, 0.5, 0.5) cornerRadius:5];
        border.lineWidth = 1;
        [border stroke];

        // hour labels every 2 hours
        [[UIColor colorWithRed:0.30 green:0.34 blue:0.42 alpha:1] setFill];
        for (NSInteger h = 0; h <= 12; h += 2) {
            NSString *t = [NSString stringWithFormat:@"%ld", (long)(row * 12 + h)];
            CGSize sz = [t sizeWithFont:font];
            CGFloat x = kPad + h * 2 * cell - sz.width / 2;
            x = MAX(kPad - 2, MIN(x, kPad + w - sz.width + 2));
            [t drawAtPoint:CGPointMake(x, y + kBarH + 1) withFont:font];
        }

        // now marker
        if (_nowSlot >= row * 24 && _nowSlot < row * 24 + 24) {
            CGFloat x = kPad + ((_nowSlot - row * 24) + _nowFraction) * cell;
            [[UIColor colorWithRed:0.86 green:0.10 blue:0.10 alpha:1] setFill];
            UIRectFill(CGRectMake(x - 1, y - 4, 2, kBarH + 8));
            CGContextFillEllipseInRect(ctx, CGRectMake(x - 4, y - 7, 8, 8));
        }
    }
}

@end
