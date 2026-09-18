#import "PlayerSettingsViewController.h"
#import "QualityPickerViewController.h"
#import "SubtitlePickerViewController.h"
#import "PlexQuality.h"

@implementation PlayerSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ajustes";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cerrar"
        style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The quality row shows the current value, which may have changed on the pushed screen.
    [self.tableView reloadData];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Built by hand rather than dequeued: Value1 shows the current setting on the right,
    // and the registered-class path only ever yields the Default style.
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                   reuseIdentifier:@"row"];
    cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (indexPath.row == 0) {
        cell.textLabel.text = @"Calidad";
        cell.detailTextLabel.text = [PlexQuality currentLabel];
    } else {
        cell.textLabel.text = @"Subtitulos";
        cell.detailTextLabel.text = (self.selectedSubtitleStreamID.integerValue != 0) ? @"Activados" : @"Ninguno";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    __weak typeof(self) weakSelf = self;

    if (indexPath.row == 0) {
        QualityPickerViewController *picker = [[QualityPickerViewController alloc] init];
        picker.onSelect = ^(NSInteger index) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf.onChangeQuality) strongSelf.onChangeQuality();
        };
        [self.navigationController pushViewController:picker animated:YES];
        return;
    }

    SubtitlePickerViewController *picker = [[SubtitlePickerViewController alloc] init];
    picker.ratingKey = self.ratingKey;
    picker.existingStreams = self.subtitleStreams;
    picker.selectedStreamID = self.selectedSubtitleStreamID ?: @0;
    picker.onSelect = ^(NSNumber *streamID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.selectedSubtitleStreamID = streamID;
        if (strongSelf.onSelectSubtitle) strongSelf.onSelectSubtitle(streamID);
    };
    [self.navigationController pushViewController:picker animated:YES];
}

@end
