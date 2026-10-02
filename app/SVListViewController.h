#import <UIKit/UIKit.h>

// Simple checkmark list. items: array of @{@"id":..., @"title":...}
@interface SVListViewController : UITableViewController
@property (nonatomic, retain) NSArray *items;
@property (nonatomic, copy) NSString *selectedId;
@property (nonatomic, copy) NSString *footerText;
@property (nonatomic, copy) void (^onSelect)(NSDictionary *item);
@property (nonatomic, copy) void (^loader)(SVListViewController *vc); // optional async loader
- (void)finishLoading:(NSArray *)items error:(NSError *)error;
@end
