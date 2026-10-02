#import <UIKit/UIKit.h>

// Draws a 24h schedule as two rows (00–12, 12–24) of 24 half-hour cells.
@interface SVTimelineView : UIView
@property (nonatomic, copy) NSString *slots;   // 48 chars
@property (nonatomic, assign) NSInteger nowSlot; // -1 = no marker
@property (nonatomic, assign) CGFloat nowFraction; // 0..1 within nowSlot
+ (CGFloat)preferredHeight;
@end

UIColor *SVColorOn(void);
UIColor *SVColorOff(void);
UIColor *SVColorMaybe(void);
UIColor *SVColorUnknown(void);
