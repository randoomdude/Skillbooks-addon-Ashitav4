addon.name = 'skillbook';
addon.author = 'OpenAI';
addon.version = '2.0';
addon.desc = 'Repeatedly uses any Inventory item selected by partial name.';
addon.link = '';

require 'common';

local chat = require 'chat';

local DEFAULT_DELAY_MS = 2000;
local MIN_DELAY_MS = 1200;

local state = {
    enabled = false,
    delay_ms = DEFAULT_DELAY_MS,
    last_use = 0,
    selected_id = 0,
    selected_name = nil,
};

local function msg(text)
    print(chat.header('SkillBook'):append(chat.message(text)));
end

local function err(text)
    print(chat.header('SkillBook'):append(chat.error(text)));
end

local function normalize(value)
    return string.lower(tostring(value or ''));
end

local function get_inventory()
    return AshitaCore:GetMemoryManager():GetInventory();
end

local function get_item_resource(item_id)
    local resource_manager = AshitaCore:GetResourceManager();
    if (resource_manager == nil) then
        return nil;
    end

    return resource_manager:GetItemById(item_id);
end

local function add_name(names, seen, value)
    if (type(value) ~= 'string' or value == '') then
        return;
    end

    local key = normalize(value);
    if (seen[key]) then
        return;
    end

    seen[key] = true;
    table.insert(names, value);
end

local function collect_resource_names(resource)
    local names = {};
    local seen = {};

    if (resource == nil) then
        return names;
    end

    local function harvest(value)
        if (type(value) == 'string') then
            add_name(names, seen, value);
            return;
        end

        if (value == nil) then
            return;
        end

        for i = 0, 4 do
            local ok, name = pcall(function()
                return value[i];
            end);

            if (ok) then
                add_name(names, seen, name);
            end
        end

        for i = 1, 4 do
            local ok, name = pcall(function()
                return value[i];
            end);

            if (ok) then
                add_name(names, seen, name);
            end
        end
    end

    harvest(resource.Name);
    harvest(resource.LogNameSingular);
    harvest(resource.LogNamePlural);
    harvest(resource.SingularName);
    harvest(resource.PluralName);

    return names;
end

local function preferred_item_name(item_id)
    local names = collect_resource_names(get_item_resource(item_id));

    for _, name in ipairs(names) do
        if (#name <= 64 and not name:find('\n', 1, true)) then
            return name;
        end
    end

    return names[1];
end

local function get_inventory_max(inventory)
    local ok, value = pcall(function()
        return inventory:GetContainerCountMax(0);
    end);

    if (ok and type(value) == 'number' and value > 0) then
        return value;
    end

    return 80;
end

local function scan_inventory()
    local inventory = get_inventory();
    local items = {};
    local by_id = {};

    if (inventory == nil) then
        return items;
    end

    for slot = 0, get_inventory_max(inventory) do
        local item = inventory:GetContainerItem(0, slot);

        if (
            item ~= nil and
            item.Id ~= nil and
            item.Id > 0 and
            item.Count ~= nil and
            item.Count > 0
        ) then
            local entry = by_id[item.Id];

            if (entry == nil) then
                local resource = get_item_resource(item.Id);

                entry = {
                    id = item.Id,
                    name = preferred_item_name(item.Id),
                    names = collect_resource_names(resource),
                    count = 0,
                };

                by_id[item.Id] = entry;
                table.insert(items, entry);
            end

            entry.count = entry.count + item.Count;
        end
    end

    table.sort(items, function(a, b)
        return normalize(a.name) < normalize(b.name);
    end);

    return items;
end

local function entry_matches(entry, query)
    local q = normalize(query);

    if (q == '') then
        return false;
    end

    if (entry.name ~= nil and normalize(entry.name):find(q, 1, true) ~= nil) then
        return true;
    end

    for _, name in ipairs(entry.names or {}) do
        if (normalize(name):find(q, 1, true) ~= nil) then
            return true;
        end
    end

    return false;
end

local function count_selected()
    if (state.selected_id == 0) then
        return 0;
    end

    local inventory = get_inventory();
    if (inventory == nil) then
        return 0;
    end

    local total = 0;

    for slot = 0, get_inventory_max(inventory) do
        local item = inventory:GetContainerItem(0, slot);

        if (item ~= nil and item.Id == state.selected_id) then
            total = total + (item.Count or 0);
        end
    end

    return total;
end

local function set_by_query(query)
    if (normalize(query) == '') then
        err('Usage: /skillbook set <part of item name>');
        return;
    end

    local matches = {};

    for _, entry in ipairs(scan_inventory()) do
        if (entry_matches(entry, query)) then
            table.insert(matches, entry);
        end
    end

    if (#matches == 0) then
        err(('No Inventory item matched "%s".'):fmt(query));
        return;
    end

    if (#matches > 1) then
        err(('"%s" matched %d Inventory items:'):fmt(query, #matches));

        for _, entry in ipairs(matches) do
            msg(('  %s x%d [ID %d]'):fmt(
                entry.name or ('Item ' .. tostring(entry.id)),
                entry.count,
                entry.id
            ));
        end

        msg('Use a longer name fragment.');
        return;
    end

    local entry = matches[1];
    state.selected_id = entry.id;
    state.selected_name = entry.name;

    msg(('Selected: %s x%d [ID %d].'):fmt(
        entry.name or ('Item ' .. tostring(entry.id)),
        entry.count,
        entry.id
    ));
end

local function list_items(query)
    local q = normalize(query);
    local shown = 0;

    for _, entry in ipairs(scan_inventory()) do
        if (q == '' or entry_matches(entry, q)) then
            local marker = (entry.id == state.selected_id) and ' <selected>' or '';

            msg(('  %s x%d [ID %d]%s'):fmt(
                entry.name or ('Item ' .. tostring(entry.id)),
                entry.count,
                entry.id,
                marker
            ));

            shown = shown + 1;
        end
    end

    if (shown == 0) then
        if (q == '') then
            msg('No items found in normal Inventory.');
        else
            msg(('No Inventory items matched "%s".'):fmt(query));
        end
    else
        msg(('Displayed %d Inventory item(s).'):fmt(shown));
    end
end

local function stop(reason)
    state.enabled = false;

    if (reason ~= nil) then
        msg(reason);
    end
end

local function start()
    if (state.selected_id == 0 or state.selected_name == nil) then
        err('No item selected. Example: /skillbook set throwing');
        return;
    end

    local count = count_selected();

    if (count <= 0) then
        err('Selected item is no longer in normal Inventory.');
        state.enabled = false;
        return;
    end

    state.enabled = true;
    state.last_use = ashita.time.get_tick64() - state.delay_ms;

    msg(('Started using %s. %d remaining; delay %.1f sec.'):fmt(
        state.selected_name,
        count,
        state.delay_ms / 1000
    ));
end

local function print_status()
    if (state.selected_id == 0) then
        msg(('Status: %s | no item selected | delay %.1f sec.'):fmt(
            state.enabled and 'ON' or 'OFF',
            state.delay_ms / 1000
        ));
        return;
    end

    msg(('Status: %s | %s x%d | delay %.1f sec.'):fmt(
        state.enabled and 'ON' or 'OFF',
        state.selected_name or ('Item ' .. tostring(state.selected_id)),
        count_selected(),
        state.delay_ms / 1000
    ));
end

local function print_help()
    msg('/skillbook set <name>      - Select ANY normal Inventory item by partial name.');
    msg('/skillbook on              - Repeatedly use the selected item.');
    msg('/skillbook off             - Stop.');
    msg('/skillbook list [text]     - List all Inventory items, or filter by text.');
    msg('/skillbook status          - Show current selection/count/status.');
    msg('/skillbook delay <seconds> - Set repeat delay; minimum 1.2 sec.');
end

local function join_args(args, start_index)
    local parts = {};

    for i = start_index, #args do
        table.insert(parts, args[i]);
    end

    return table.concat(parts, ' ');
end

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args();

    if (#args == 0) then
        return;
    end

    local root = string.lower(args[1]);

    -- /itemloop remains available as an alias for the generic behavior.
    if (root ~= '/skillbook' and root ~= '/itemloop') then
        return;
    end

    e.blocked = true;

    if (#args == 1) then
        print_status();
        return;
    end

    local cmd = string.lower(args[2]);

    if (cmd == 'set' or cmd == 'select') then
        set_by_query(join_args(args, 3));
        return;
    end

    if (cmd == 'on' or cmd == 'start') then
        start();
        return;
    end

    if (cmd == 'off' or cmd == 'stop') then
        stop('Stopped.');
        return;
    end

    if (cmd == 'status') then
        print_status();
        return;
    end

    if (cmd == 'list') then
        list_items(join_args(args, 3));
        return;
    end

    if (cmd == 'delay' and #args >= 3) then
        local seconds = tonumber(args[3]);

        if (seconds == nil) then
            err('Delay must be a number. Example: /skillbook delay 2');
            return;
        end

        local ms = math.floor(seconds * 1000);

        if (ms < MIN_DELAY_MS) then
            ms = MIN_DELAY_MS;
            msg('Delay clamped to the 1.2 second minimum.');
        end

        state.delay_ms = ms;
        msg(('Delay set to %.1f seconds.'):fmt(state.delay_ms / 1000));
        return;
    end

    if (cmd == 'help') then
        print_help();
        return;
    end

    print_help();
end);

ashita.events.register('d3d_present', 'present_cb', function()
    if (not state.enabled) then
        return;
    end

    local now = ashita.time.get_tick64();

    if ((now - state.last_use) < state.delay_ms) then
        return;
    end

    local count = count_selected();

    if (count <= 0) then
        stop(('No %s remain in Inventory; stopped automatically.'):fmt(
            state.selected_name or 'selected items'
        ));
        return;
    end

    state.last_use = now;

    AshitaCore:GetChatManager():QueueCommand(
        -1,
        ('/item "%s" <me>'):fmt(state.selected_name)
    );
end);

ashita.events.register('unload', 'unload_cb', function()
    state.enabled = false;
end);
