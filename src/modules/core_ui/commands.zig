const Rect = @import("context.zig").Rect;
pub const rich_text = @import("rich_text.zig");
pub const WidgetId = u64;

pub const PanelCommand = struct {
    id: WidgetId,
    rect: Rect,
};

pub const TextCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    spans: rich_text.RichText = &.{},
    muted: bool = false,
};

pub const LabelCommand = TextCommand;

pub const ButtonCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    hovered: bool,
    active: bool,
    disabled: bool = false,
};

pub const IconButtonCommand = struct {
    id: WidgetId,
    rect: Rect,
    icon: []const u8,
    hovered: bool,
    active: bool,
    toggled: bool = false,
};

pub const ToggleCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    value: bool,
    hovered: bool,
    active: bool,
};

pub const ToggleGroupItemCommand = struct {
    id: WidgetId,
    group_id: WidgetId,
    rect: Rect,
    text: []const u8,
    selected: bool,
    hovered: bool,
    active: bool,
};

pub const SeparatorCommand = struct {
    id: WidgetId,
    rect: Rect,
};

pub const SpacerCommand = struct {
    id: WidgetId,
    rect: Rect,
};

pub const TextInputCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    cursor: usize,
    focused: bool,
    hovered: bool,
};

pub const NumberInputCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    value: f32,
    dragging: bool,
    hovered: bool,
    focused: bool,
};

pub const SliderCommand = struct {
    id: WidgetId,
    rect: Rect,
    track_rect: Rect,
    fill_rect: Rect,
    value: f32,
    hovered: bool,
    active: bool,
};

pub const CheckboxCommand = struct {
    id: WidgetId,
    rect: Rect,
    box_rect: Rect,
    text: []const u8,
    checked: bool,
    hovered: bool,
    active: bool,
};

pub const SelectCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    open: bool,
    hovered: bool,
    active: bool,
};

pub const SelectItemCommand = struct {
    id: WidgetId,
    select_id: WidgetId,
    rect: Rect,
    text: []const u8,
    selected: bool,
    hovered: bool,
};

pub const TabCommand = struct {
    id: WidgetId,
    bar_id: WidgetId,
    rect: Rect,
    text: []const u8,
    selected: bool,
    hovered: bool,
    active: bool,
};

pub const TreeNodeCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    depth: u32,
    open: bool,
    hovered: bool,
    active: bool,
};

pub const SelectableCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    text_pad_x: f32 = 8.0,
    selected: bool,
    hovered: bool,
    active: bool,
};

pub const PreviewColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const AssetPreviewShape = enum {
    box,
    cylinder,
    plane,
    sphere,
    region_map,
};

pub const AssetPreviewCommand = struct {
    id: WidgetId,
    rect: Rect,
    thumbnail_rect: Rect,
    text_rect: Rect,
    label: []const u8,
    detail: []const u8 = "",
    fill_color: PreviewColor,
    accent_color: PreviewColor,
    shape: AssetPreviewShape,
    preview_mask: u16 = 0,
    selected: bool,
    hovered: bool,
    active: bool,
};

pub const ScrollAreaCommand = struct {
    id: WidgetId,
    rect: Rect,
    clip_rect: Rect,
    scroll_y: f32,
    content_height: f32 = 0.0,
    max_scroll: f32 = 0.0,
};

pub const ScrollAreaEndCommand = struct {};

pub const TooltipCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    spans: rich_text.RichText = &.{},
};

pub const StatusLabelCommand = TextCommand;

pub const BadgeCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    variant: BadgeVariant,
};

pub const BadgeVariant = enum {
    neutral,
    accent,
    err,
    warning,
};

pub const CollapsingHeaderCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    open: bool,
    hovered: bool,
    active: bool,
};

pub const ProgressBarCommand = struct {
    id: WidgetId,
    rect: Rect,
    fill_rect: Rect,
    value: f32,
    indeterminate: bool = false,
    marquee_offset: f32 = 0.0,
};

pub const TableHeaderCellCommand = struct {
    id: WidgetId,
    table_id: WidgetId,
    rect: Rect,
    text: []const u8,
    column_index: u32,
    sort_active: bool,
    sort_asc: bool,
    hovered: bool,
    active: bool,
};

pub const TableRowCommand = struct {
    id: WidgetId,
    table_id: WidgetId,
    rect: Rect,
    row_index: u32,
    selected: bool,
    hovered: bool,
    active: bool,
};

pub const TableCellCommand = struct {
    id: WidgetId,
    table_id: WidgetId,
    row_id: WidgetId,
    rect: Rect,
    text: []const u8,
};

pub const ComboboxCommand = struct {
    id: WidgetId,
    rect: Rect,
    text_rect: Rect,
    arrow_rect: Rect,
    text: []const u8,
    open: bool,
    focused: bool,
    hovered: bool,
    active: bool,
};

pub const ComboboxItemCommand = struct {
    id: WidgetId,
    combobox_id: WidgetId,
    rect: Rect,
    text: []const u8,
    selected: bool,
    highlighted: bool,
    hovered: bool,
};

pub const SplitPaneCommand = struct {
    id: WidgetId,
    rect: Rect,
    handle_rect: Rect,
    axis: SplitAxis,
    dragging: bool,
    hovered: bool,
};

pub const SplitAxis = enum {
    horizontal,
    vertical,
};

pub const SpinnerSize = enum {
    small,
    medium,
};

pub const SpinnerCommand = struct {
    id: WidgetId,
    rect: Rect,
    label_rect: ?Rect,
    label: ?[]const u8,
    size: SpinnerSize,
    rotation: f32,
};

pub const InlineAlertCommand = struct {
    id: WidgetId,
    rect: Rect,
    text: []const u8,
    variant: InlineAlertVariant,
};

pub const InlineAlertVariant = enum {
    info,
    warning,
    err,
};

pub const RenderCommand = union(enum) {
    panel: PanelCommand,
    label: LabelCommand,
    text: TextCommand,
    button: ButtonCommand,
    icon_button: IconButtonCommand,
    toggle: ToggleCommand,
    toggle_group_item: ToggleGroupItemCommand,
    separator: SeparatorCommand,
    spacer: SpacerCommand,
    text_input: TextInputCommand,
    number_input: NumberInputCommand,
    slider: SliderCommand,
    checkbox: CheckboxCommand,
    select: SelectCommand,
    select_item: SelectItemCommand,
    tab: TabCommand,
    tree_node: TreeNodeCommand,
    selectable: SelectableCommand,
    asset_preview: AssetPreviewCommand,
    scroll_area: ScrollAreaCommand,
    scroll_area_end: ScrollAreaEndCommand,
    tooltip: TooltipCommand,
    status_label: StatusLabelCommand,
    badge: BadgeCommand,
    collapsing_header: CollapsingHeaderCommand,
    progress_bar: ProgressBarCommand,
    inline_alert: InlineAlertCommand,
    table_header_cell: TableHeaderCellCommand,
    table_row: TableRowCommand,
    table_cell: TableCellCommand,
    combobox: ComboboxCommand,
    combobox_item: ComboboxItemCommand,
    split_pane: SplitPaneCommand,
    spinner: SpinnerCommand,
};
