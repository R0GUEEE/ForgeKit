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

@interface FKUnityViewController : UITableViewController
@end

@interface FKScriptConsoleViewController : UIViewController
@end

@interface FKShellViewController : UIViewController
@end

@interface FKUtilitiesViewController : FKListViewController
@end

@interface FKExplorerViewController : FKListViewController
@end

@interface FKFlexViewController : UIViewController
@end

@interface FKAgentSettingsViewController : FKListViewController
@end
@interface FKAgentChatViewController : UIViewController
@end
