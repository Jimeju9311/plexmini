#import "QualityPickerViewController.h"
#import "PlexQuality.h"

@implementation QualityPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Calidad";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[PlexQuality levels] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"El servidor reconvierte el video en cada reproduccion, porque este iPad no "
            "puede decodificar HEVC por hardware. Bajar la calidad alivia al servidor y a "
            "la red; 1080p es lo maximo que aprovecha esta pantalla.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    cell.textLabel.textColor = [UIColor whiteColor];

    NSDictionary *level = [PlexQuality levels][indexPath.row];
    NSInteger mbps = [level[@"bitrate"] integerValue] / 1000;
    cell.textLabel.text = [NSString stringWithFormat:@"%@  ·  hasta %ld Mbps", level[@"label"], (long)mbps];
    cell.accessoryType = (indexPath.row == [PlexQuality selectedIndex])
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == [PlexQuality selectedIndex]) return; // no need to rebuild the session

    [PlexQuality setSelectedIndex:indexPath.row];
    [self.tableView reloadData];
    if (self.onSelect) self.onSelect(indexPath.row);
}

@end
