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
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
    self.navigationItem.rightBarButtonItem = refresh;
    [self reload];
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
            return;
        }
        NSDictionary *container = json[@"MediaContainer"];
        NSArray *directory = container[@"Directory"];
        NSArray *metadata = container[@"Metadata"];
        self.items = directory ?: metadata ?: @[];
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (NSString *)subtitleForItem:(NSDictionary *)item {
    NSString *type = item[@"type"];
    if ([type isEqualToString:@"episode"]) {
        NSNumber *season = item[@"parentIndex"];
        NSNumber *episode = item[@"index"];
        return [NSString stringWithFormat:@"T%@E%@", season ?: @0, episode ?: @0];
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
