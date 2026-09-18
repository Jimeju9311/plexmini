#import "PlexListViewController.h"
#import "PlexCell.h"
#import "PlexClient.h"
#import "PlexConfig.h"
#import "PlexDetailViewController.h"

@implementation PlexListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.rowHeight = 96;
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.tableView registerClass:[PlexCell class] forCellReuseIdentifier:@"cell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"plain"];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
    self.navigationItem.rightBarButtonItem = refresh;

    // Pull down to refresh: the refresh button is easy to miss, and new content shows up
    // on the server while a list is already on screen.
    UIRefreshControl *pull = [[UIRefreshControl alloc] init];
    pull.tintColor = [UIColor whiteColor];
    [pull addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = pull;

    [self reload];
}

// The root screen leads with a "recently added" shortcut, so new films and episodes are
// one tap away instead of having to be hunted down inside their library.
- (BOOL)showsRecentlyAddedSection {
    return self.isTopLevel;
}

- (BOOL)isRecentlyAddedRow:(NSIndexPath *)indexPath {
    return [self showsRecentlyAddedSection] && indexPath.section == 0;
}

- (void)reload {
    NSString *urlStr = [NSString stringWithFormat:@"%@%@", PLEX_SERVER, self.fetchPath];
    [PlexClient getJSON:[NSURL URLWithString:urlStr] completion:^(id json, NSError *error) {
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                message:[NSString stringWithFormat:@"No se pudo cargar: %@", error.localizedDescription]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self.refreshControl endRefreshing];
            return;
        }
        NSDictionary *container = json[@"MediaContainer"];
        NSArray *directory = container[@"Directory"];
        NSArray *metadata = container[@"Metadata"];
        self.items = directory ?: metadata ?: @[];
        [self.tableView reloadData];
        [self.refreshControl endRefreshing];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self showsRecentlyAddedSection] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self showsRecentlyAddedSection] && section == 0) return 1;
    return self.items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (![self showsRecentlyAddedSection]) return nil;
    return section == 0 ? @"Novedades" : @"Bibliotecas";
}

- (NSString *)subtitleForItem:(NSDictionary *)item {
    NSString *type = item[@"type"];
    if ([type isEqualToString:@"episode"]) {
        NSNumber *season = item[@"parentIndex"];
        NSNumber *episode = item[@"index"];
        NSString *code = [NSString stringWithFormat:@"T%@E%@", season ?: @0, episode ?: @0];
        // Inside a season the show is obvious from context, but in a mixed list (the
        // recently-added screen) "T1E2" alone doesn't say which show it belongs to.
        NSString *show = item[@"grandparentTitle"];
        if ([show isKindOfClass:[NSString class]] && show.length > 0) {
            return [NSString stringWithFormat:@"%@ · %@", show, code];
        }
        return code;
    }
    if ([type isEqualToString:@"movie"]) {
        NSNumber *year = item[@"year"];
        return year ? [year stringValue] : @"";
    }
    NSNumber *count = item[@"leafCount"] ?: item[@"childCount"];
    if (count) return [NSString stringWithFormat:@"%@ elementos", count];
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isRecentlyAddedRow:indexPath]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"plain" forIndexPath:indexPath];
        cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.text = @"Anadido recientemente";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    PlexCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *item = self.items[indexPath.row];
    cell.textLabel.text = item[@"title"] ?: @"(sin titulo)";
    cell.detailTextLabel.text = [self subtitleForItem:item];
    cell.imageView.image = nil;

    NSString *thumb = item[@"thumb"] ?: item[@"parentThumb"] ?: item[@"grandparentThumb"];
    NSURL *imgURL = [PlexClient imageURLForThumb:thumb];
    cell.loadingURL = imgURL;
    [PlexClient loadImage:imgURL completion:^(UIImage *image) {
        if ([cell.loadingURL isEqual:imgURL]) {
            cell.imageView.image = image;
            [cell setNeedsLayout];
        }
    }];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self isRecentlyAddedRow:indexPath]) {
        PlexListViewController *next = [[PlexListViewController alloc] init];
        next.title = @"Anadido recientemente";
        // Capped because this spans every library at once and the default is unbounded.
        next.fetchPath = @"/library/recentlyAdded?X-Plex-Container-Start=0&X-Plex-Container-Size=60";
        next.isTopLevel = NO;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    NSDictionary *item = self.items[indexPath.row];

    if (self.isTopLevel) {
        NSString *key = item[@"key"];
        PlexListViewController *next = [[PlexListViewController alloc] init];
        next.title = item[@"title"];
        next.fetchPath = [NSString stringWithFormat:@"/library/sections/%@/all", key];
        next.isTopLevel = NO;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    NSString *type = item[@"type"];
    if ([type isEqualToString:@"show"] || [type isEqualToString:@"season"]) {
        // Prefer the item's own "key" - Plex already gives a ready-to-use path there
        // (e.g. "/library/metadata/555/allLeaves" for a virtual "All episodes" node
        // on a flattened show, which has no ratingKey/children of its own). Only fall
        // back to building "/library/metadata/{ratingKey}/children" when "key" is
        // missing or isn't a real path.
        NSString *key = item[@"key"];
        NSString *fetchPath = nil;
        if ([key isKindOfClass:[NSString class]] && [key hasPrefix:@"/"]) {
            fetchPath = key;
        } else {
            id ratingKey = item[@"ratingKey"];
            if (ratingKey) {
                fetchPath = [NSString stringWithFormat:@"/library/metadata/%@/children", ratingKey];
            }
        }
        if (!fetchPath) {
            return; // malformed entry, nothing sensible to navigate to
        }
        PlexListViewController *next = [[PlexListViewController alloc] init];
        next.title = item[@"title"];
        next.fetchPath = fetchPath;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    PlexDetailViewController *detail = [[PlexDetailViewController alloc] init];
    detail.item = item;
    [self.navigationController pushViewController:detail animated:YES];
}

@end
