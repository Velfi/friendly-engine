pub const ProjectManagerEntry = struct {
    name: []u8,
    path: []u8,
    renderer: []u8,
    tags: []u8,
    last_opened: []u8,
    status: []u8,
};

pub const InputMode = enum {
    none,
    create,
    manage_presets,
    preset_name,
    about,
};

pub const PresetNameAction = enum {
    none,
    new,
    rename,
};

pub const ListFilter = enum {
    all,
    recent,
};

pub const PendingDialogKind = enum {
    none,
    import_folder,
    relocate_folder,
};
