//
//  FKPanelScreens.h — internal screen declarations for the toolkit panel
//

#import "ForgeKit.h"

@interface FKServerViewController : UIViewController
@end

@interface FKRuntimeViewController : UIViewController
@end

@interface FKDefaultsViewController : UITableViewController
@end

@interface FKKeychainViewController : UITableViewController
@end

@interface FKSettingsViewController : UIViewController
@end

@interface FKLogViewController : UITableViewController
+ (instancetype)logController;
@end
