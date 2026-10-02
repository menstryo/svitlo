#import "SVListViewController.h"

@interface SVListViewController () {
    UIActivityIndicatorView *_spinner;
    NSString *_errorText;
}
@end

@implementation SVListViewController

@synthesize items = _items, selectedId = _selectedId, footerText = _footerText, onSelect = _onSelect, loader = _loader;

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)dealloc {
    [_items release];
    [_selectedId release];
    [_footerText release];
    [_onSelect release];
    [_loader release];
    [_spinner release];
    [_errorText release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.loader && !self.items) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [_spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:_spinner] autorelease];
        self.loader(self);
    }
}

- (void)finishLoading:(NSArray *)items error:(NSError *)error {
    [_spinner stopAnimating];
    self.navigationItem.rightBarButtonItem = nil;
    self.items = items;
    [_errorText release];
    _errorText = error ? [[error localizedDescription] copy] : nil;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.items.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (_errorText) return [@"Не вдалося завантажити: " stringByAppendingString:_errorText];
    return self.footerText;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) c = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"] autorelease];
    NSDictionary *it = [self.items objectAtIndex:ip.row];
    c.textLabel.text = [it objectForKey:@"title"];
    BOOL sel = [[it objectForKey:@"id"] isEqual:self.selectedId];
    c.accessoryType = sel ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    c.textLabel.textColor = sel ? [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1] : [UIColor blackColor];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *it = [self.items objectAtIndex:ip.row];
    self.selectedId = [it objectForKey:@"id"];
    [tv reloadData];
    if (self.onSelect) self.onSelect(it);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
