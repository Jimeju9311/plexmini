#import "SubtitlePickerViewController.h"
#import "SubtitleSearchResultsViewController.h"
#import "PlexClient.h"

@implementation SubtitlePickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Subtitulos";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    if (!self.selectedStreamID) self.selectedStreamID = @0;

    // When pushed onto an existing stack (from the detail screen) this replaces the
    // automatic back button, which still just pops - no functional loss. When presented
    // as the root of its own modal navigation controller (from the player's settings
    // button) there was otherwise NO way to leave this screen at all.
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cerrar"
        style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
}

- (void)closeTapped {
    if (self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (1 + self.existingStreams.count) : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"En este archivo" : @"Buscar en linea";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Ninguno";
            if (self.selectedStreamID.integerValue == 0) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            NSDictionary *s = self.existingStreams[indexPath.row - 1];
            cell.textLabel.text = s[@"extendedDisplayTitle"] ?: s[@"displayTitle"] ?: s[@"language"] ?: @"Subtitulo";
            NSNumber *sid = s[@"id"];
            if (sid && [self.selectedStreamID isEqual:sid]) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    } else {
        cell.textLabel.text = indexPath.row == 0 ? @"Buscar en espanol" : @"Buscar en ingles";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSNumber *sid = indexPath.row == 0 ? @0 : self.existingStreams[indexPath.row - 1][@"id"];
        self.selectedStreamID = sid ?: @0;
        if (self.onSelect) self.onSelect(self.selectedStreamID);
        [self.tableView reloadData];
        return;
    }

    NSString *lang = indexPath.row == 0 ? @"es" : @"en";
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spin.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    [spin startAnimating];
    [self.view addSubview:spin];

    __weak typeof(self) weakSelf = self;
    [PlexClient searchSubtitlesForRatingKey:self.ratingKey language:lang completion:^(NSArray *results, NSError *error) {
        [spin removeFromSuperview];
        if (error || results.count == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sin resultados"
                message:error ? error.localizedDescription : @"No se encontraron subtitulos para ese idioma (puede que el servidor no tenga un proveedor de subtitulos configurado)."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        SubtitleSearchResultsViewController *resultsVC = [[SubtitleSearchResultsViewController alloc] init];
        resultsVC.ratingKey = weakSelf.ratingKey;
        resultsVC.results = results;
        [weakSelf.navigationController pushViewController:resultsVC animated:YES];
    }];
}

@end
