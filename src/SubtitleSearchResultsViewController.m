#import "SubtitleSearchResultsViewController.h"
#import "PlexClient.h"

@implementation SubtitleSearchResultsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Resultados";
    self.view.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundColor = [UIColor blackColor];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *r = self.results[indexPath.row];
    cell.textLabel.text = r[@"title"] ?: r[@"displayTitle"] ?: r[@"key"] ?: @"(sin nombre)";
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.text = r[@"languageCode"] ?: r[@"language"] ?: @"";
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *r = self.results[indexPath.row];
    NSString *key = r[@"key"];
    if (![key isKindOfClass:[NSString class]]) return;

    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spin.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    [spin startAnimating];
    [self.view addSubview:spin];

    __weak typeof(self) weakSelf = self;
    [PlexClient downloadSubtitleForRatingKey:self.ratingKey key:key completion:^(BOOL ok) {
        [spin removeFromSuperview];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:ok ? @"Descargando" : @"Error"
            message:ok ? @"El subtitulo se esta descargando en el servidor. Vuelve a abrir el selector de subtitulos en unos segundos para elegirlo." : @"No se pudo descargar el subtitulo."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (ok && weakSelf.onDownloaded) weakSelf.onDownloaded();
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    }];
}

@end
