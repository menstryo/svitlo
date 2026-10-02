#import "SVMainViewController.h"
#import "SVSettingsViewController.h"
#import "SVTimelineView.h"
#import "SVStore.h"

#pragma mark - status icon

@interface SVBulbView : UIView
@property (nonatomic, retain) UIColor *color;
@property (nonatomic, assign) BOOL dark;
@end

@implementation SVBulbView
@synthesize color = _color, dark = _dark;
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; }
    return self;
}
- (void)dealloc { [_color release]; [super dealloc]; }
- (void)setColor:(UIColor *)c { [_color release]; _color = [c retain]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 3, 3);
    // soft shadow + filled circle
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 2, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
    [(self.color ?: SVColorUnknown()) setFill];
    CGContextFillEllipseInRect(ctx, r);
    CGContextRestoreGState(ctx);
    // gloss
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, r);
    CGContextClip(ctx);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = { 1, 1, 1, 0.55, 1, 1, 1, 0.0 };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextDrawLinearGradient(ctx, g, CGPointMake(0, r.origin.y), CGPointMake(0, CGRectGetMidY(r)), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(ctx);
    // bolt
    CGFloat w = r.size.width, x = r.origin.x, y = r.origin.y;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(x + w * 0.56, y + w * 0.14)];
    [p addLineToPoint:CGPointMake(x + w * 0.30, y + w * 0.56)];
    [p addLineToPoint:CGPointMake(x + w * 0.49, y + w * 0.56)];
    [p addLineToPoint:CGPointMake(x + w * 0.42, y + w * 0.88)];
    [p addLineToPoint:CGPointMake(x + w * 0.72, y + w * 0.42)];
    [p addLineToPoint:CGPointMake(x + w * 0.52, y + w * 0.42)];
    [p closePath];
    [[UIColor colorWithWhite:1 alpha:self.dark ? 0.55 : 0.95] setFill];
    [p fill];
    [[UIColor colorWithWhite:0 alpha:0.15] setStroke];
    p.lineWidth = 1;
    [p stroke];
}
@end

#pragma mark - legend

@interface SVLegendView : UIView
@end
@implementation SVLegendView
- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    NSArray *cols = @[SVColorOn(), SVColorOff(), SVColorMaybe()];
    NSArray *txt = @[@"є світло", @"немає", @"можливо"];
    UIFont *f = [UIFont systemFontOfSize:13];
    CGFloat total = 0;
    for (NSString *t in txt) total += 14 + 5 + [t sizeWithFont:f].width + 16;
    CGFloat x = floorf((self.bounds.size.width - total + 16) / 2);
    for (NSUInteger i = 0; i < 3; i++) {
        [[cols objectAtIndex:i] setFill];
        UIBezierPath *b = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, 8, 14, 14) cornerRadius:3];
        [b fill];
        [[UIColor colorWithWhite:0 alpha:0.25] setStroke];
        [b stroke];
        x += 19;
        NSString *t = [txt objectAtIndex:i];
        [[UIColor whiteColor] setFill];
        [t drawAtPoint:CGPointMake(x, 7) withFont:f];
        [[UIColor colorWithRed:0.30 green:0.34 blue:0.42 alpha:1] setFill];
        [t drawAtPoint:CGPointMake(x, 6) withFont:f];
        x += [t sizeWithFont:f].width + 16;
    }
}
@end

#pragma mark - main

enum { kRowTimeline = 0 };

@interface SVMainViewController () {
    NSTimer *_timer;
    NSString *_lastError;
    BOOL _didAutoOpenSettings;
}
@end

@implementation SVMainViewController

- (id)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Світло";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeUpdated)
                                                     name:SVStoreDidUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appActive)
                                                     name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    [_lastError release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Налаштування"
                                                                              style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(openSettings)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                             target:self action:@selector(refresh)] autorelease];
    UIRefreshControl *rc = [[[UIRefreshControl alloc] init] autorelease];
    [rc addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = rc;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    SVStore *st = [SVStore shared];
    if ((!st.regionId || !st.queue) && !_didAutoOpenSettings) {
        _didAutoOpenSettings = YES;
        [self openSettings];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)appActive {
    SVStore *st = [SVStore shared];
    if (!st.regionId) return;
    [self.tableView reloadData];
    if (!st.fetchedAt || [[NSDate date] timeIntervalSinceDate:st.fetchedAt] > 10 * 60) [self refresh];
}

- (void)tick {
    [self.tableView reloadData];
}

- (void)storeUpdated {
    [self.tableView reloadData];
}

- (void)refresh {
    SVStore *st = [SVStore shared];
    if (!st.regionId) { [self.refreshControl endRefreshing]; [self openSettings]; return; }
    [st refresh:^(NSError *error) {
        [self.refreshControl endRefreshing];
        [_lastError release];
        _lastError = error ? [[error localizedDescription] copy] : nil;
        [self.tableView reloadData];
    }];
}

- (void)openSettings {
    SVSettingsViewController *s = [[[SVSettingsViewController alloc] init] autorelease];
    UINavigationController *nav = [[[UINavigationController alloc] initWithRootViewController:s] autorelease];
    nav.navigationBar.tintColor = self.navigationController.navigationBar.tintColor;
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - model

- (BOOL)configured {
    SVStore *st = [SVStore shared];
    return st.regionId && st.queue;
}

- (NSString *)allSlots {
    SVStore *st = [SVStore shared];
    return [[st todaySlots] stringByAppendingString:[st tomorrowSlots]];
}

- (NSString *)whenText:(NSInteger)k {
    NSString *t = [SVStore timeForSlot:k];
    return k >= 48 ? [@"завтра о " stringByAppendingString:t] : [@"о " stringByAppendingString:t];
}

- (NSString *)inText:(NSInteger)k {
    NSDate *d = [[SVStore shared] dateForSlot:k dayOffset:0];
    return [SVStore durationText:[d timeIntervalSinceNow]];
}

// returns title, subtitle, color
- (NSArray *)statusInfo {
    SVStore *st = [SVStore shared];
    NSString *all = [self allSlots];
    NSInteger i = [st currentSlotIndex];
    unichar c = [all characterAtIndex:i];

    if (c == '?') {
        if (!st.schedule) return @[@"Немає даних", st.loading ? @"Завантаження…" : @"Потягніть вниз, щоб оновити", SVColorUnknown()];
        return @[@"Графіка немає", @"Обленерго ще не опублікувало графік на сьогодні", SVColorUnknown()];
    }

    if (c == '0') {
        for (NSInteger k = i + 1; k < (NSInteger)all.length; k++) {
            unichar n = [all characterAtIndex:k];
            if (n == '?') break;
            if (n == '1') return @[@"Світло є", [NSString stringWithFormat:@"Відключення %@ · через %@", [self whenText:k], [self inText:k]], SVColorOn()];
            if (n == '2') return @[@"Світло є", [NSString stringWithFormat:@"Можливе відключення %@ · через %@", [self whenText:k], [self inText:k]], SVColorOn()];
        }
        return @[@"Світло є", [st hasTomorrow] ? @"Сьогодні й завтра відключень не заплановано" : @"До кінця дня відключень не заплановано", SVColorOn()];
    }

    if (c == '1') {
        for (NSInteger k = i + 1; k < (NSInteger)all.length; k++) {
            unichar n = [all characterAtIndex:k];
            if (n == '?') break;
            if (n == '0') return @[@"Світла немає", [NSString stringWithFormat:@"Увімкнуть %@ · через %@", [self whenText:k], [self inText:k]], SVColorOff()];
            if (n == '2') return @[@"Світла немає", [NSString stringWithFormat:@"Далі можливе відключення %@", [self whenText:k]], SVColorOff()];
        }
        return @[@"Світла немає", @"До кінця доби за графіком", SVColorOff()];
    }

    // maybe
    for (NSInteger k = i + 1; k < (NSInteger)all.length; k++) {
        unichar n = [all characterAtIndex:k];
        if (n != '2') {
            if (n == '?') break;
            return @[@"Можливе відключення", [NSString stringWithFormat:@"До %@ · ще %@", [SVStore timeForSlot:k], [self inText:k]], SVColorMaybe()];
        }
    }
    return @[@"Можливе відключення", @"До кінця доби", SVColorMaybe()];
}

- (NSString *)dayTitle:(NSInteger)offset {
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    f.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"uk_UA"] autorelease];
    f.dateFormat = @"d MMMM";
    NSString *d = [f stringFromDate:[[SVStore shared] dateForSlot:0 dayOffset:offset]];
    return [NSString stringWithFormat:@"%@, %@", offset == 0 ? @"Сьогодні" : @"Завтра", d];
}

- (NSString *)slotsForSection:(NSInteger)s {
    return s == 1 ? [[SVStore shared] todaySlots] : [[SVStore shared] tomorrowSlots];
}

- (BOOL)knownSlots:(NSString *)s { return [s rangeOfString:@"?"].location == NSNotFound; }

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return [self configured] ? 3 : 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (![self configured]) return 1;
    if (s == 0) return 1;
    NSString *slots = [self slotsForSection:s];
    if (![self knownSlots:slots]) return 1;
    NSInteger n = [[SVStore shared] intervalsForSlots:slots].count;
    return 1 + MAX(n, 1);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (![self configured] || s == 0) return nil;
    return [self dayTitle:s - 1];
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    if ([self configured] && s == 1) return 30;
    return UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    if ([self configured] && s == 1) {
        return [[[SVLegendView alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 30)] autorelease];
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    SVStore *st = [SVStore shared];
    if (![self configured]) return @"Виберіть область і свою чергу — програма покаже, коли буде світло, і нагадає про відключення.";
    if (s != 2) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    if (_lastError) [parts addObject:[NSString stringWithFormat:@"Не вдалося оновити: %@", _lastError]];
    if ([st sourceUpdated]) [parts addObject:[NSString stringWithFormat:@"Графік обленерго: %@", [st sourceUpdated]]];
    if (st.fetchedAt) {
        NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
        f.dateFormat = @"dd.MM HH:mm";
        [parts addObject:[NSString stringWithFormat:@"Завантажено: %@", [f stringFromDate:st.fetchedAt]]];
    }
    return [parts componentsJoinedByString:@"\n"];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (![self configured]) return 60;
    if (ip.section == 0) return 92;
    if (ip.row == kRowTimeline && [self knownSlots:[self slotsForSection:ip.section]]) return [SVTimelineView preferredHeight];
    return 44;
}

- (UITableViewCell *)statusCell {
    SVStore *st = [SVStore shared];
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray *info = [self statusInfo];

    SVBulbView *bulb = [[[SVBulbView alloc] initWithFrame:CGRectMake(10, 16, 60, 60)] autorelease];
    bulb.color = [info objectAtIndex:2];
    bulb.dark = [[info objectAtIndex:2] isEqual:SVColorOff()];
    [c.contentView addSubview:bulb];

    CGFloat x = 80, w = c.contentView.bounds.size.width - x - 10;
    UILabel *t = [[[UILabel alloc] initWithFrame:CGRectMake(x, 12, w, 26)] autorelease];
    t.font = [UIFont boldSystemFontOfSize:21];
    t.text = [info objectAtIndex:0];
    t.backgroundColor = [UIColor clearColor];
    t.adjustsFontSizeToFitWidth = YES;
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [c.contentView addSubview:t];

    UILabel *sub = [[[UILabel alloc] initWithFrame:CGRectMake(x, 38, w, 36)] autorelease];
    sub.font = [UIFont systemFontOfSize:14];
    sub.textColor = [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1];
    sub.numberOfLines = 2;
    sub.text = [info objectAtIndex:1];
    sub.backgroundColor = [UIColor clearColor];
    sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [c.contentView addSubview:sub];

    UILabel *loc = [[[UILabel alloc] initWithFrame:CGRectMake(x, 72, w, 16)] autorelease];
    loc.font = [UIFont systemFontOfSize:12];
    loc.textColor = [UIColor grayColor];
    loc.text = [NSString stringWithFormat:@"%@ · черга %@", st.regionName ?: @"", st.queue];
    loc.backgroundColor = [UIColor clearColor];
    loc.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [c.contentView addSubview:loc];
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SVStore *st = [SVStore shared];

    if (![self configured]) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
        c.textLabel.text = @"Вибрати регіон і чергу";
        c.detailTextLabel.text = @"Графіки відключень по всій Україні";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    if (ip.section == 0) return [self statusCell];

    NSString *slots = [self slotsForSection:ip.section];
    BOOL known = [self knownSlots:slots];

    if (ip.row == kRowTimeline) {
        UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        if (!known) {
            c.textLabel.text = st.schedule ? @"Графік ще не опубліковано" : @"Немає даних";
            c.textLabel.textColor = [UIColor grayColor];
            c.textLabel.font = [UIFont systemFontOfSize:15];
            c.textLabel.textAlignment = NSTextAlignmentCenter;
            return c;
        }
        SVTimelineView *tl = [[[SVTimelineView alloc] initWithFrame:CGRectInset(c.contentView.bounds, 0, 0)] autorelease];
        tl.frame = CGRectMake(0, 0, c.contentView.bounds.size.width, [SVTimelineView preferredHeight]);
        tl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        tl.slots = slots;
        if (ip.section == 1) {
            NSInteger now = [st currentSlotIndex];
            NSDate *slotStart = [st dateForSlot:now dayOffset:0];
            tl.nowFraction = MAX(0, MIN(1, [[NSDate date] timeIntervalSinceDate:slotStart] / 1800.0));
            tl.nowSlot = now;
        }
        [c.contentView addSubview:tl];
        return c;
    }

    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray *iv = [st intervalsForSlots:slots];
    if (iv.count == 0) {
        c.textLabel.text = @"Відключень не заплановано";
        c.textLabel.font = [UIFont systemFontOfSize:16];
        c.imageView.image = nil;
        return c;
    }
    NSDictionary *it = [iv objectAtIndex:ip.row - 1];
    NSInteger from = [[it objectForKey:@"from"] integerValue];
    NSInteger to = [[it objectForKey:@"to"] integerValue];
    BOOL maybe = [[it objectForKey:@"kind"] isEqualToString:@"2"];
    c.textLabel.text = [NSString stringWithFormat:@"%@ – %@", [SVStore timeForSlot:from], to >= 48 ? @"24:00" : [SVStore timeForSlot:to]];
    c.textLabel.font = [UIFont boldSystemFontOfSize:17];
    c.detailTextLabel.text = maybe ? @"можливо" : [NSString stringWithFormat:@"без світла · %@", [SVStore durationText:(to - from) * 1800]];

    // past intervals are dimmed
    if (ip.section == 1 && to <= [st currentSlotIndex]) {
        c.textLabel.textColor = [UIColor lightGrayColor];
        c.detailTextLabel.textColor = [UIColor lightGrayColor];
    }

    // small color chip
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(14, 14), NO, 0);
    [(maybe ? SVColorMaybe() : SVColorOff()) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 14, 14) cornerRadius:3] fill];
    c.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (![self configured]) [self openSettings];
}

@end
