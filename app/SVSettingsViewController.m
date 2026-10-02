#import "SVSettingsViewController.h"
#import "SVListViewController.h"
#import "SVStore.h"

enum { kSecPlace, kSecNotify, kSecServer, kSecAbout, kSecCount };

@interface SVSettingsViewController () {
    UITextField *_serverField;
    UISwitch *_notifySwitch;
}
@end

@implementation SVSettingsViewController

- (id)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"Налаштування";
    }
    return self;
}

- (void)dealloc {
    [_serverField release];
    [_notifySwitch release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                            target:self action:@selector(done)] autorelease];

    _serverField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 280, 24)];
    _serverField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _serverField.font = [UIFont systemFontOfSize:15];
    _serverField.textColor = [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1];
    _serverField.keyboardType = UIKeyboardTypeURL;
    _serverField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _serverField.autocorrectionType = UITextAutocorrectionTypeNo;
    _serverField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _serverField.returnKeyType = UIReturnKeyDone;
    _serverField.placeholder = @"https://нік.github.io/svitlo";
    _serverField.delegate = self;
    _serverField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"serverURL"];

    _notifySwitch = [[UISwitch alloc] init];
    _notifySwitch.on = [SVStore shared].notifyEnabled;
    [_notifySwitch addTarget:self action:@selector(notifyChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)saveServer {
    NSString *s = [_serverField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length) [SVStore shared].serverURL = s;
}

- (void)done {
    [_serverField resignFirstResponder];
    [self saveServer];
    [[SVStore shared] rescheduleNotifications];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    [self saveServer];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)tf {
    [self saveServer];
}

- (void)notifyChanged:(UISwitch *)sw {
    [SVStore shared].notifyEnabled = sw.on;
    [[SVStore shared] rescheduleNotifications];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSecNotify] withRowAnimation:UITableViewRowAnimationFade];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return kSecCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case kSecPlace: return 2;
        case kSecNotify: return [SVStore shared].notifyEnabled ? 2 : 1;
        case kSecServer: return 1;
        case kSecAbout: return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case kSecPlace: return @"Місце";
        case kSecNotify: return @"Сповіщення";
        case kSecServer: return @"Сервер";
        case kSecAbout: return @"Про програму";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case kSecPlace: return @"Свою чергу можна дізнатися на сайті обленерго або в рахунку за світло.";
        case kSecNotify: return @"Нагадування спрацюють навіть якщо програма закрита — після кожного оновлення графіка вони переплановуються.";
        case kSecServer: return @"Звідки брати графіки. За замовчуванням — GitHub Pages, де дані оновлюються кожні 10 хвилин.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SVStore *st = [SVStore shared];
    UITableViewCell *c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease];

    if (ip.section == kSecPlace) {
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (ip.row == 0) {
            c.textLabel.text = @"Регіон";
            c.detailTextLabel.text = st.regionName ?: @"Не вибрано";
        } else {
            c.textLabel.text = @"Черга";
            c.detailTextLabel.text = st.queue ?: @"Не вибрано";
        }
    } else if (ip.section == kSecNotify) {
        if (ip.row == 0) {
            c.textLabel.text = @"Нагадувати";
            c.accessoryView = _notifySwitch;
            c.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            c.textLabel.text = @"Заздалегідь";
            c.detailTextLabel.text = [NSString stringWithFormat:@"за %ld хв", (long)st.notifyMinutes];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (ip.section == kSecServer) {
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        _serverField.frame = CGRectInset(c.contentView.bounds, 10, 10);
        _serverField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [c.contentView addSubview:_serverField];
    } else if (ip.section == kSecAbout) {
        if (ip.row == 0) {
            c.textLabel.text = @"Версія";
            c.detailTextLabel.text = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
            c.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            c.textLabel.text = @"Розробник";
            c.detailTextLabel.text = @"t.me/menstryo";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [_serverField resignFirstResponder];
    SVStore *st = [SVStore shared];

    if (ip.section == kSecPlace && ip.row == 0) {
        [self saveServer];
        SVListViewController *l = [[[SVListViewController alloc] init] autorelease];
        l.title = @"Регіон";
        l.selectedId = st.regionId;
        l.footerText = @"Показано регіони, для яких є відкриті дані графіків.";
        l.loader = ^(SVListViewController *vc) {
            [st fetchRegions:^(NSArray *regions, NSError *error) {
                NSMutableArray *items = [NSMutableArray array];
                for (NSDictionary *r in regions) {
                    [items addObject:@{ @"id": [r objectForKey:@"id"], @"title": [r objectForKey:@"name"] }];
                }
                [vc finishLoading:items error:error];
            }];
        };
        l.onSelect = ^(NSDictionary *it) {
            BOOL changed = ![[it objectForKey:@"id"] isEqual:st.regionId];
            st.regionId = [it objectForKey:@"id"];
            st.regionName = [it objectForKey:@"title"];
            if (changed) {
                st.queue = nil;
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"queue"];
                [st refresh:nil];
            }
        };
        [self.navigationController pushViewController:l animated:YES];
    } else if (ip.section == kSecPlace && ip.row == 1) {
        if (!st.regionId) {
            UIAlertView *a = [[[UIAlertView alloc] initWithTitle:@"Спершу виберіть регіон" message:nil delegate:nil
                                               cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
            [a show];
            return;
        }
        SVListViewController *l = [[[SVListViewController alloc] init] autorelease];
        l.title = @"Черга";
        l.selectedId = st.queue;
        void (^fill)(SVListViewController *, NSError *) = ^(SVListViewController *vc, NSError *err) {
            NSMutableArray *items = [NSMutableArray array];
            for (NSString *q in [st queueIds]) {
                [items addObject:@{ @"id": q, @"title": [NSString stringWithFormat:@"Черга %@", q] }];
            }
            [vc finishLoading:items error:(items.count ? nil : err)];
        };
        if ([st queueIds].count) {
            fill(l, nil);
        } else {
            l.loader = ^(SVListViewController *vc) {
                [st refresh:^(NSError *error) { fill(vc, error); }];
            };
        }
        l.onSelect = ^(NSDictionary *it) {
            st.queue = [it objectForKey:@"id"];
            [st rescheduleNotifications];
        };
        [self.navigationController pushViewController:l animated:YES];
    } else if (ip.section == kSecNotify && ip.row == 1) {
        SVListViewController *l = [[[SVListViewController alloc] init] autorelease];
        l.title = @"Заздалегідь";
        NSMutableArray *items = [NSMutableArray array];
        for (NSNumber *m in @[@5, @10, @15, @30, @60]) {
            [items addObject:@{ @"id": m, @"title": [NSString stringWithFormat:@"за %@ хв", m] }];
        }
        l.items = items;
        l.selectedId = (id)@(st.notifyMinutes);
        l.onSelect = ^(NSDictionary *it) {
            st.notifyMinutes = [[it objectForKey:@"id"] integerValue];
            [st rescheduleNotifications];
        };
        [self.navigationController pushViewController:l animated:YES];
    } else if (ip.section == kSecAbout && ip.row == 1) {
        NSURL *tg = [NSURL URLWithString:@"tg://resolve?domain=menstryo"];
        if (![[UIApplication sharedApplication] canOpenURL:tg]) tg = [NSURL URLWithString:@"https://t.me/menstryo"];
        [[UIApplication sharedApplication] openURL:tg];
    }
}

@end
