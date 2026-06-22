#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum FeMenuAction {
    FE_MENU_NONE = 0,
    FE_MENU_NEW_PROJECT = 1,
    FE_MENU_IMPORT_PROJECT = 2,
    FE_MENU_OPEN_PROJECT = 3,
    FE_MENU_QUIT = 4,
    FE_MENU_ABOUT = 5,
    FE_MENU_REMOVE_FROM_LIST = 6,
} FeMenuAction;

void fe_menubar_install(void);
bool fe_menubar_poll_action(int *out_action);

#ifdef __cplusplus
}
#endif
