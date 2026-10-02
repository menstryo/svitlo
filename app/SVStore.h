#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Slot chars: '0' on, '1' off, '2' maybe, '?' unknown
extern NSString * const SVStoreDidUpdateNotification;

@interface SVStore : NSObject

+ (SVStore *)shared;

// settings
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *regionId;
@property (nonatomic, copy) NSString *regionName;
@property (nonatomic, copy) NSString *queue;
@property (nonatomic, assign) BOOL notifyEnabled;
@property (nonatomic, assign) NSInteger notifyMinutes;

// data
@property (nonatomic, retain, readonly) NSDictionary *schedule;   // last schedule JSON for regionId
@property (nonatomic, retain, readonly) NSDate *fetchedAt;
@property (nonatomic, assign, readonly) BOOL loading;

- (void)fetchRegions:(void (^)(NSArray *regions, NSError *error))done;
- (void)refresh:(void (^)(NSError *error))done;

// helpers based on schedule + queue
- (NSArray *)queueIds;
- (NSString *)todaySlots;      // 48 chars, '?' if unknown
- (NSString *)tomorrowSlots;   // 48 chars, '?' if unknown
- (BOOL)hasTomorrow;
- (NSInteger)currentSlotIndex; // 0..47
- (NSDate *)dateForSlot:(NSInteger)slot dayOffset:(NSInteger)day;
- (NSString *)sourceUpdated;
- (NSArray *)intervalsForSlots:(NSString *)slots; // array of @{@"from":..,@"to":..,@"kind":..}

- (void)rescheduleNotifications;

+ (NSString *)timeForSlot:(NSInteger)slot;
+ (NSString *)durationText:(NSTimeInterval)secs;

@end
