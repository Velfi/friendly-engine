#import <Cocoa/Cocoa.h>
#include "menubar.h"

static volatile int g_pending_action = FE_MENU_NONE;

@interface FeMenuHandler : NSObject
- (void)handleMenu:(id)sender;
@end

static FeMenuHandler *g_handler = nil;

@implementation FeMenuHandler
- (void)handleMenu:(id)sender {
    if (![sender isKindOfClass:[NSMenuItem class]]) return;
    g_pending_action = (int)[(NSMenuItem *)sender tag];
}
@end

static void add_item(NSMenu *menu, const char *title, FeMenuAction action, const char *key, NSEventModifierFlags modifiers) {
    NSString *label = [NSString stringWithUTF8String:title];
    NSString *key_equiv = key ? [NSString stringWithUTF8String:key] : @"";
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:label action:@selector(handleMenu:) keyEquivalent:key_equiv];
    [item setTag:action];
    [item setTarget:g_handler];
    if (modifiers != 0) {
        [item setKeyEquivalentModifierMask:modifiers];
    }
    [menu addItem:item];
}

void fe_menubar_install(void) {
    if (g_handler == nil) {
        g_handler = [[FeMenuHandler alloc] init];
    }

    NSMenu *main_menu = [[NSMenu alloc] init];

    NSMenuItem *app_menu_item = [[NSMenuItem alloc] init];
    NSMenu *app_menu = [[NSMenu alloc] initWithTitle:@"Friendly Engine"];
    add_item(app_menu, "About friendly-engine editor", FE_MENU_ABOUT, "", 0);
    [app_menu addItem:[NSMenuItem separatorItem]];
    add_item(app_menu, "Quit friendly-engine editor", FE_MENU_QUIT, "q", NSEventModifierFlagCommand);
    [app_menu_item setSubmenu:app_menu];
    [main_menu addItem:app_menu_item];

    NSMenuItem *file_item = [[NSMenuItem alloc] initWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *file_menu = [[NSMenu alloc] initWithTitle:@"File"];
    add_item(file_menu, "New Project...", FE_MENU_NEW_PROJECT, "n", NSEventModifierFlagCommand);
    add_item(file_menu, "Import Project...", FE_MENU_IMPORT_PROJECT, "i", NSEventModifierFlagCommand);
    add_item(file_menu, "Open Project", FE_MENU_OPEN_PROJECT, "o", NSEventModifierFlagCommand);
    [file_menu addItem:[NSMenuItem separatorItem]];
    add_item(file_menu, "Remove from List", FE_MENU_REMOVE_FROM_LIST, "", 0);
    [file_item setSubmenu:file_menu];
    [main_menu addItem:file_item];

    NSMenuItem *help_item = [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    NSMenu *help_menu = [[NSMenu alloc] initWithTitle:@"Help"];
    add_item(help_menu, "About friendly-engine editor", FE_MENU_ABOUT, "", 0);
    [help_item setSubmenu:help_menu];
    [main_menu addItem:help_item];

    [NSApp setMainMenu:main_menu];
}

bool fe_menubar_poll_action(int *out_action) {
    int action = g_pending_action;
    if (action == FE_MENU_NONE) return false;
    g_pending_action = FE_MENU_NONE;
    *out_action = action;
    return true;
}
