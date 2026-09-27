addon.name = 'skillbook';
addon.author = 'OpenAI';
addon.version = '1.1';
addon.desc = 'Automatically uses any FFXI skill-up book from Inventory.';
addon.link = '';

require 'common';

local chat = require 'chat';

local DEFAULT_DELAY_MS = 2000;
local MIN_DELAY_MS = 1200;

-- Known retail skill-up books.
-- Both full/common names and resource abbreviations are included where FFXI
-- resources / wikis commonly abbreviate the item name.
local known_books = T{
    -- Combat skills
    "mikhe's memo",
    "dagger enchiridion", "dgr. enchiridion",
    "swing and stab",
    "mieuseloir's diary",
    "striking bull's diary", "bull's diary",
    "death for dimwits", "death for dim.",
    "ludwig's report",
    "clash of titans",
    "kagetora's diary",
    "noillurie's log",
    "ferreous's diary",
    "kayeel-payeel's memoirs", "k-p's memoirs",
    "perih's primer",
    "barrels of fun",
    "throwing weapon enchiridion", "t.w. enchiridion",
    "mikhe's note",
    "sonia's diary",
    "the successor",
    "kagetora's journal", "kage. journal",

    -- Magic skills
    "altana's hymn",
    "coveffe musings",
    "aid for all",
    "investigative report", "inv. report",
    "bounty list",
    "dark deeds",
    "breezy libretto",
    "cavernous score",
    "beaming score",
    "yomi's diagram",
    "astral homeland",
    "life-form study",
    "hrohj's record",
    "the bell tolls",
};

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

local function normalize(s)
    if (s == nil) then return ''; end
    return string.lower(tostring(s));
end

local function is_known_book_name(name)
    local n = normalize(name);
    return known_books:contains(n);
end

local function get_resource_name(item_id)
    local res = AshitaCore:GetResourceManager():GetItemById(item_id);
    if (res == nil) then
        return nil;
    end

    -- English resource name is normally Name[0] in Ashita v4.
    local name = res.Name[0];
    if (name == nil or name == '') then
        return nil;
    end

    return name;
end

local function scan_inventory_books()
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local found = {};

    if (inv == nil) then
        return found;
    end

    -- Container 0 = normal Inventory. Usable items must be accessible there
    -- for the regular /item command.
    local max = inv:GetContainerCountMax(0);
    if (max == nil or max <= 0) then
        max = 80;
    end

    for slot = 0, max do
        local item = inv:GetContainerItem(0, slot);

        if (item ~= nil and item.Id ~= nil and item.Id > 0 and item.Count ~= nil and item.Count > 0) then
            local name = get_resource_name(item.Id);

            if (name ~= nil and is_known_book_name(name)) then
                local existing = nil;

                for _, v in ipairs(found) do
                    if (v.id == item.Id) then
                        existing = v;
                        break;
                    end
                end

                if (existing ~= nil) then
                    existing.count = existing.count + item.Count;
                else
                    table.insert(found, {
                        id = item.Id,
                        name = name,
                        count = item.Count,
                    });
                end
            end
        end
    end

    table.sort(found, function(a, b)
        return normalize(a.name) < normalize(b.name);
    end);

    return found;
end

local function count_selected()
    if (state.selected_id == 0) then
        return 0;
    end

    local inv = AshitaCore:GetMemoryManager():GetInventory();
    if (inv == nil) then
        return 0;
    end

    local total = 0;
    local max = inv:GetContainerCountMax(0);
    if (max == nil or max <= 0) then
        max = 80;
    end

    for slot = 0, max do
        local item = inv:GetContainerItem(0, slot);
        if (item ~= nil and item.Id == state.selected_id) then
            total = total + item.Count;
        end
    end

    return total;
end

local function select_book(book)
    if (book == nil) then
        state.selected_id = 0;
        state.selected_name = nil;
        return;
    end

    state.selected_id = book.id;
    state.selected_name = book.name;
    msg(('Selected: %s (%d in Inventory).'):fmt(book.name, book.count));
end

local function auto_select()
    local books = scan_inventory_books();

    if (#books == 0) then
        err('No recognized skill-up books found in normal Inventory.');
        return false;
    end

    -- Keep the currently selected book if it is still present.
    if (state.selected_id ~= 0) then
        for _, book in ipairs(books) do
            if (book.id == state.selected_id) then
                state.selected_name = book.name;
                return true;
            end
        end
    end

    select_book(books[1]);

    if (#books > 1) then
        msg(('Found %d different skill books. Use /skillbook list or /skillbook set <name> to choose another.'):fmt(#books));
    end

    return true;
end

local function stop(reason)
    state.enabled = false;
    if (reason ~= nil) then
        msg(reason);
    end
end

local function start()
    if (not auto_select()) then
        state.enabled = false;
        return;
    end

    local count = count_selected();
    if (count <= 0) then
        err('Selected book is no longer in Inventory.');
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

local function list_books()
    local books = scan_inventory_books();

    if (#books == 0) then
        msg('No recognized skill-up books found in normal Inventory.');
        return;
    end

    msg(('Skill-up books in Inventory (%d types):'):fmt(#books));

    for _, book in ipairs(books) do
        local marker = (book.id == state.selected_id) and '  <selected>' or '';
        msg(('  %s x%d%s'):fmt(book.name, book.count, marker));
    end
end

local function set_by_query(query)
    local q = normalize(query);
    if (q == '') then
        err('Usage: /skillbook set <part of book name>');
        return;
    end

    local books = scan_inventory_books();
    local matches = {};

    for _, book in ipairs(books) do
        if (normalize(book.name):find(q, 1, true) ~= nil) then
            table.insert(matches, book);
        end
    end

    if (#matches == 0) then
        err(('No skill-up book in Inventory matched "%s".'):fmt(query));
        return;
    end

    if (#matches > 1) then
        err(('"%s" matched more than one book:'):fmt(query));
        for _, book in ipairs(matches) do
            msg(('  %s x%d'):fmt(book.name, book.count));
        end
        msg('Use a longer name fragment.');
        return;
    end

    select_book(matches[1]);
end

local function print_status()
    if (state.selected_id == 0) then
        msg(('Status: %s | no book selected | delay %.1f sec.'):fmt(
            state.enabled and 'ON' or 'OFF',
            state.delay_ms / 1000
        ));
        return;
    end

    msg(('Status: %s | %s x%d | delay %.1f sec.'):fmt(
        state.enabled and 'ON' or 'OFF',
        state.selected_name or 'Unknown',
        count_selected(),
        state.delay_ms / 1000
    ));
end

local function print_help()
    msg('/skillbook on              - Start using the selected book; auto-selects if needed.');
    msg('/skillbook off             - Stop.');
    msg('/skillbook list            - List recognized skill books in Inventory.');
    msg('/skillbook set <name>      - Select by partial name, e.g. /skillbook set yomi');
    msg('/skillbook status          - Show current book/count/status.');
    msg('/skillbook delay <seconds> - Set repeat delay; minimum 1.2 sec.');
end

local function join_args(args, start_index)
    local parts = {};
    for i = start_index, #args do
        table.insert(parts, args[i]);
    end
    return table.concat(parts, ' ');
end

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();

    if (#args == 0 or string.lower(args[1]) ~= '/skillbook') then
        return;
    end

    e.blocked = true;

    if (#args == 1) then
        print_status();
        return;
    end

    local cmd = string.lower(args[2]);

    if (cmd == 'on' or cmd == 'start') then
        start();
        return;
    end

    if (cmd == 'off' or cmd == 'stop') then
        stop('Stopped.');
        return;
    end

    if (cmd == 'list') then
        list_books();
        return;
    end

    if (cmd == 'set' or cmd == 'select') then
        set_by_query(join_args(args, 3));
        return;
    end

    if (cmd == 'status') then
        print_status();
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

ashita.events.register('d3d_present', 'present_cb', function ()
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
            state.selected_name or 'selected skill books'
        ));
        return;
    end

    state.last_use = now;

    -- Use the exact item name read from Ashita's retail resource table.
    -- This queues the normal FFXI /item command and does not simulate keyboard input.
    local command = ('/item "%s" <me>'):fmt(state.selected_name);
    AshitaCore:GetChatManager():QueueCommand(-1, command);
end);

ashita.events.register('unload', 'unload_cb', function ()
    state.enabled = false;
end);
