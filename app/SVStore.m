#import "SVStore.h"

NSString * const SVStoreDidUpdateNotification = @"SVStoreDidUpdateNotification";

static NSString * const kDefaultServer = @"https://menstryo.github.io/svitlo";

@interface SVStore ()
@property (nonatomic, retain, readwrite) NSDictionary *schedule;
@property (nonatomic, retain, readwrite) NSDate *fetchedAt;
@property (nonatomic, assign, readwrite) BOOL loading;
@end

// NSURLConnection wrapper that trusts the server certificate of our own data host.
// iOS 6 has an outdated root store; the data is public, so a broken chain is acceptable here.
@interface SVRequest : NSObject {
    NSURLConnection *_conn;
    NSMutableData *_data;
    NSURLResponse *_resp;
    void (^_done)(NSURLResponse *, NSData *, NSError *);
}
+ (void)start:(NSURLRequest *)req done:(void (^)(NSURLResponse *, NSData *, NSError *))done;
@end

@implementation SVRequest

+ (void)start:(NSURLRequest *)req done:(void (^)(NSURLResponse *, NSData *, NSError *))done {
    SVRequest *r = [[SVRequest alloc] init]; // released when finished
    r->_done = [done copy];
    r->_data = [[NSMutableData alloc] init];
    r->_conn = [[NSURLConnection alloc] initWithRequest:req delegate:r startImmediately:NO];
    [r->_conn scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [r->_conn start];
}

- (void)dealloc {
    [_conn release];
    [_data release];
    [_resp release];
    [_done release];
    [super dealloc];
}

- (void)finish:(NSError *)err {
    if (_done) _done(_resp, err ? nil : _data, err);
    [self autorelease];
}

- (void)connection:(NSURLConnection *)c willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)ch {
    if ([ch.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        NSURLCredential *cred = [NSURLCredential credentialForTrust:ch.protectionSpace.serverTrust];
        [ch.sender useCredential:cred forAuthenticationChallenge:ch];
    } else {
        [ch.sender performDefaultHandlingForAuthenticationChallenge:ch];
    }
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r {
    [_resp release]; _resp = [r retain];
    [_data setLength:0];
}
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)d { [_data appendData:d]; }
- (void)connectionDidFinishLoading:(NSURLConnection *)c { [self finish:nil]; }
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)e { [self finish:e]; }
- (NSCachedURLResponse *)connection:(NSURLConnection *)c willCacheResponse:(NSCachedURLResponse *)r { return nil; }

@end

@implementation SVStore

@synthesize schedule = _schedule, fetchedAt = _fetchedAt, loading = _loading;

+ (SVStore *)shared {
    static SVStore *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SVStore alloc] init]; });
    return s;
}

- (id)init {
    if ((self = [super init])) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d registerDefaults:@{ @"serverURL": kDefaultServer,
                               @"notifyEnabled": @YES,
                               @"notifyMinutes": @15 }];
        [self loadCache];
    }
    return self;
}

- (void)dealloc {
    [_schedule release];
    [_fetchedAt release];
    [super dealloc];
}

#pragma mark - settings

- (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }

- (NSString *)serverURL {
    NSString *s = [[self d] stringForKey:@"serverURL"];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    if (s.length && [s rangeOfString:@"://"].location == NSNotFound) s = [@"http://" stringByAppendingString:s];
    return s;
}
- (void)setServerURL:(NSString *)v { [[self d] setObject:v forKey:@"serverURL"]; [[self d] synchronize]; }

- (NSString *)regionId { return [[self d] stringForKey:@"regionId"]; }
- (void)setRegionId:(NSString *)v {
    if (![v isEqualToString:self.regionId]) {
        self.schedule = nil;
        self.fetchedAt = nil;
    }
    [[self d] setObject:v forKey:@"regionId"]; [[self d] synchronize];
    [self loadCache];
}

- (NSString *)regionName { return [[self d] stringForKey:@"regionName"]; }
- (void)setRegionName:(NSString *)v { [[self d] setObject:v forKey:@"regionName"]; [[self d] synchronize]; }

- (NSString *)queue { return [[self d] stringForKey:@"queue"]; }
- (void)setQueue:(NSString *)v { [[self d] setObject:v forKey:@"queue"]; [[self d] synchronize]; }

- (BOOL)notifyEnabled { return [[self d] boolForKey:@"notifyEnabled"]; }
- (void)setNotifyEnabled:(BOOL)v { [[self d] setBool:v forKey:@"notifyEnabled"]; [[self d] synchronize]; }

- (NSInteger)notifyMinutes { return [[self d] integerForKey:@"notifyMinutes"]; }
- (void)setNotifyMinutes:(NSInteger)v { [[self d] setInteger:v forKey:@"notifyMinutes"]; [[self d] synchronize]; }

#pragma mark - cache

- (NSString *)cachePath {
    if (!self.regionId) return nil;
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"schedule-%@.json", self.regionId]];
}

- (void)loadCache {
    NSString *p = [self cachePath];
    NSData *data = p ? [NSData dataWithContentsOfFile:p] : nil;
    if (!data) return;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        self.schedule = obj;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:NULL];
        self.fetchedAt = [attrs fileModificationDate];
    }
}

#pragma mark - network

- (void)getPath:(NSString *)path done:(void (^)(id json, NSData *raw, NSError *error))done {
    NSString *base = self.serverURL;
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:path]];
    if (!url || [base rangeOfString:@"YOUR-SUBDOMAIN"].location != NSNotFound) {
        NSError *e = [NSError errorWithDomain:@"Svitlo" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Вкажіть адресу сервера в налаштуваннях"}];
        done(nil, nil, e);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:25];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [SVRequest start:req done:^(NSURLResponse *resp, NSData *data, NSError *err) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        if (err || !data) { done(nil, nil, err ?: [NSError errorWithDomain:@"Svitlo" code:2 userInfo:nil]); return; }
        NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 200;
        NSError *jerr = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr];
        if (code >= 400) {
            NSString *msg = [obj isKindOfClass:[NSDictionary class]] ? [obj objectForKey:@"error"] : nil;
            done(nil, nil, [NSError errorWithDomain:@"Svitlo" code:code
                                           userInfo:@{NSLocalizedDescriptionKey: msg ?: [NSString stringWithFormat:@"Помилка сервера %ld", (long)code]}]);
            return;
        }
        if (!obj) { done(nil, nil, jerr); return; }
        done(obj, data, nil);
    }];
}

- (void)fetchRegions:(void (^)(NSArray *, NSError *))done {
    [self getPath:@"/regions.json" done:^(id json, NSData *raw, NSError *error) {
        NSArray *regions = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"regions"] : nil;
        done(regions, error);
    }];
}

- (void)refresh:(void (^)(NSError *))done {
    if (!self.regionId) { if (done) done(nil); return; }
    self.loading = YES;
    NSString *rid = [[self.regionId copy] autorelease];
    [self getPath:[NSString stringWithFormat:@"/schedule/%@.json", rid] done:^(id json, NSData *raw, NSError *error) {
        self.loading = NO;
        if (!error && [json isKindOfClass:[NSDictionary class]] && [rid isEqualToString:self.regionId]) {
            self.schedule = json;
            self.fetchedAt = [NSDate date];
            [raw writeToFile:[self cachePath] atomically:YES];
            [self rescheduleNotifications];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SVStoreDidUpdateNotification object:self];
        if (done) done(error);
    }];
}

#pragma mark - time helpers

+ (NSTimeZone *)kyiv {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:@"Europe/Kiev"];
    if (!tz) tz = [NSTimeZone timeZoneWithName:@"Europe/Kyiv"];
    return tz ?: [NSTimeZone localTimeZone];
}

+ (NSCalendar *)calendar {
    NSCalendar *c = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
    c.timeZone = [self kyiv];
    return c;
}

- (NSString *)deviceDateString {
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    f.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease];
    f.timeZone = [SVStore kyiv];
    f.dateFormat = @"yyyy-MM-dd";
    return [f stringFromDate:[NSDate date]];
}

- (NSDate *)midnightToday {
    NSCalendar *c = [SVStore calendar];
    NSDateComponents *dc = [c components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[NSDate date]];
    return [c dateFromComponents:dc];
}

- (NSDate *)dateForSlot:(NSInteger)slot dayOffset:(NSInteger)day {
    NSCalendar *c = [SVStore calendar];
    NSDateComponents *dc = [[[NSDateComponents alloc] init] autorelease];
    dc.day = day;
    dc.minute = slot * 30;
    return [c dateByAddingComponents:dc toDate:[self midnightToday] options:0];
}

- (NSInteger)currentSlotIndex {
    NSCalendar *c = [SVStore calendar];
    NSDateComponents *dc = [c components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:[NSDate date]];
    NSInteger i = dc.hour * 2 + dc.minute / 30;
    return MAX(0, MIN(47, i));
}

+ (NSString *)timeForSlot:(NSInteger)slot {
    if (slot >= 48) slot -= 48;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(slot / 2), (long)((slot % 2) * 30)];
}

+ (NSString *)durationText:(NSTimeInterval)secs {
    NSInteger m = (NSInteger)ceil(secs / 60.0);
    if (m < 1) m = 1;
    NSInteger h = m / 60; m = m % 60;
    if (h && m) return [NSString stringWithFormat:@"%ld год %ld хв", (long)h, (long)m];
    if (h) return [NSString stringWithFormat:@"%ld год", (long)h];
    return [NSString stringWithFormat:@"%ld хв", (long)m];
}

#pragma mark - schedule helpers

- (NSDictionary *)queueDict {
    NSArray *qs = [self.schedule objectForKey:@"queues"];
    if (![qs isKindOfClass:[NSArray class]]) return nil;
    for (NSDictionary *q in qs) {
        if ([[q objectForKey:@"id"] isEqual:self.queue]) return q;
    }
    return nil;
}

- (NSArray *)queueIds {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *q in [self.schedule objectForKey:@"queues"]) {
        id i = [q objectForKey:@"id"];
        if ([i isKindOfClass:[NSString class]]) [a addObject:i];
    }
    return a;
}

static NSString *validSlots(id s) {
    if ([s isKindOfClass:[NSString class]] && [s length] == 48) return s;
    return nil;
}

static NSString *unknownSlots(void) {
    return [@"" stringByPaddingToLength:48 withString:@"?" startingAtIndex:0];
}

// returns slots for device's today (offset 0) or tomorrow (offset 1)
- (NSString *)slotsForOffset:(NSInteger)offset {
    NSDictionary *q = [self queueDict];
    if (!q) return nil;
    NSString *dev = [self deviceDateString];
    NSString *sToday = [self.schedule objectForKey:@"today"];
    NSString *sTomorrow = [self.schedule objectForKey:@"tomorrow"];
    if ([dev isEqualToString:sToday]) {
        return validSlots([q objectForKey:offset == 0 ? @"today" : @"tomorrow"]);
    }
    if ([dev isEqualToString:sTomorrow] && offset == 0) {
        return validSlots([q objectForKey:@"tomorrow"]);
    }
    return nil;
}

- (NSString *)todaySlots { return [self slotsForOffset:0] ?: unknownSlots(); }
- (NSString *)tomorrowSlots { return [self slotsForOffset:1] ?: unknownSlots(); }
- (BOOL)hasTomorrow { return [self slotsForOffset:1] != nil; }

- (NSString *)sourceUpdated {
    id u = [self.schedule objectForKey:@"updated"];
    return [u isKindOfClass:[NSString class]] ? u : nil;
}

- (NSArray *)intervalsForSlots:(NSString *)slots {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger i = 0;
    while (i < (NSInteger)slots.length) {
        unichar ch = [slots characterAtIndex:i];
        NSInteger j = i;
        while (j < (NSInteger)slots.length && [slots characterAtIndex:j] == ch) j++;
        if (ch == '1' || ch == '2') {
            [out addObject:@{ @"from": @(i), @"to": @(j), @"kind": [NSString stringWithCharacters:&ch length:1] }];
        }
        i = j;
    }
    return out;
}

#pragma mark - notifications

- (void)rescheduleNotifications {
    UIApplication *app = [UIApplication sharedApplication];
    [app cancelAllLocalNotifications];
    if (!self.notifyEnabled || !self.queue || !self.schedule) return;

    NSString *all = [[self todaySlots] stringByAppendingString:[self tomorrowSlots]];
    NSTimeInterval lead = self.notifyMinutes * 60.0;
    NSDate *now = [NSDate date];
    NSInteger count = 0;

    for (NSInteger i = 1; i < (NSInteger)all.length && count < 60; i++) {
        unichar prev = [all characterAtIndex:i - 1];
        unichar cur = [all characterAtIndex:i];
        if (prev == cur || cur == '?' || prev == '?') continue;

        NSString *body = nil;
        NSString *t = [SVStore timeForSlot:i];
        if (cur == '1') body = [NSString stringWithFormat:@"О %@ вимкнуть світло (черга %@)", t, self.queue];
        else if (cur == '2') body = [NSString stringWithFormat:@"О %@ можливе відключення (черга %@)", t, self.queue];
        else if (cur == '0' && prev == '1') body = [NSString stringWithFormat:@"О %@ мають увімкнути світло (черга %@)", t, self.queue];
        if (!body) continue;

        NSDate *at = [[self dateForSlot:i dayOffset:0] dateByAddingTimeInterval:-lead];
        if ([at compare:now] != NSOrderedDescending) continue;

        UILocalNotification *n = [[[UILocalNotification alloc] init] autorelease];
        n.fireDate = at;
        n.timeZone = nil;
        n.alertBody = body;
        n.soundName = UILocalNotificationDefaultSoundName;
        [app scheduleLocalNotification:n];
        count++;
    }
}

@end
