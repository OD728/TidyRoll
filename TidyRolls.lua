-- Tidy Roll
-- Group loot rolls as compact bars in Daylight UI's look:
--   [item icon] [need] [greed] [disenchant] [pass] [==== item name ===== time]
-- Hover the icon or bar for the item and who picked what. When the roll is
-- over the bar shows the winner for a few seconds, then goes away.
--
--   /tidyrolls          show or hide sample bars
--   /tidyrolls unlock   drag the bars where you want them (/tidyrolls lock when done)
--   /tidyrolls reset    put them back in the default spot

-- ---------------------------------------------------------------------
-- Settings: change these as you like.
local SCALE           = 1.15   -- overall size (1 = original, 1.15 = 15% bigger)
local WIDTH           = 340    -- width of a bar
local ROW_HEIGHT      = 30     -- height of a bar
local GAP             = 4      -- space between bars
local GROW_UP         = true   -- new bars stack upward (false: downward)
local HIDE_AFTER_ROLL = false  -- true: a bar goes away as soon as you pick
local SHOW_WON        = 8      -- seconds a finished bar stays when you won
local SHOW_LOST       = 4      -- seconds a finished bar stays when someone else won
local SHOW_DISENCHANT = false  -- true: show the Disenchant button too
local FONT            = STANDARD_TEXT_FONT   -- any font path works here
local FONT_SIZES      = { tiny = 9, small = 11 }
local BACKGROUND      = { 0.06, 0.06, 0.06, 0.85 }   -- the bar's dark backdrop
local BORDER          = { 0.3, 0.3, 0.3, 1 }         -- the outline
local ROUND           = true   -- small rounded corners (false: square, 1px outline)
local CORNER          = 10     -- how big the corners are (8 to 16 looks right)
local ROUND_ICON      = false  -- true: rounded item icon too (makes it look smaller)

-- Text colors.
local COLORS = {
    VALUE = { 1, 1, 1 },          -- plain text
    LABEL = { 1, 0.82, 0 },       -- gold
    GOOD  = { 0.3, 0.85, 0.3 },   -- need
    GREED = { 0.35, 0.6, 1 },     -- greed
    BAD   = { 1, 0.3, 0.3 },      -- BoP, can't pick
    OFF   = { 0.55, 0.55, 0.55 }, -- pass, waiting
}
-- ---------------------------------------------------------------------

local issecret = issecretvalue or function() return false end
local function plain(v) if issecret(v) then return nil end return v end

local function ink(key)
    local c = COLORS[key]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

-- The look: a dark box with a thin outline (rounded with ROUND), outlined
-- text, flat bars.
local FLAT = "Interface\\Buttons\\WHITE8x8"
local ROUND_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"   -- the game's rounded tooltip edge

-- corner: the corner size for this box (smaller for the bar inside a row).
-- Returns how far the inside sits from the edge.
local function skin(frame, corner)
    if ROUND then
        corner = corner or CORNER
        local inset = math.max(2, math.floor(corner / 4))
        frame:SetBackdrop({ bgFile = FLAT, edgeFile = ROUND_EDGE, edgeSize = corner,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
        frame:SetBackdropColor(unpack(BACKGROUND))
        frame:SetBackdropBorderColor(unpack(BORDER))
        return inset
    end
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(unpack(BACKGROUND))
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    return 1
end

local function text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, FONT_SIZES[size] or FONT_SIZES.small, "OUTLINE")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    return fs
end

local function makeBar(parent)
    local corner = math.max(6, CORNER - 2)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local inset = skin(holder, corner)
    holder:SetBackdropColor(0, 0, 0, 0.5)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetStatusBarTexture(FLAT)
    bar.holder = holder
    if not ROUND then
        bar:SetPoint("TOPLEFT", inset, -inset)
        bar:SetPoint("BOTTOMRIGHT", -inset, inset)
        return bar
    end
    -- Rounded: the outline is drawn above the fill, and the fill tucks a
    -- pixel under it, so the outline's curve hides the fill's square corners.
    holder:SetBackdropBorderColor(0, 0, 0, 0)
    local tuck = math.max(1, inset - 1)
    bar:SetPoint("TOPLEFT", tuck, -tuck)
    bar:SetPoint("BOTTOMRIGHT", -tuck, tuck)
    local edge = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    edge:SetAllPoints(holder)
    edge:SetFrameLevel(bar:GetFrameLevel() + 2)
    edge:SetBackdrop({ edgeFile = ROUND_EDGE, edgeSize = corner })
    edge:SetBackdropBorderColor(unpack(BORDER))
    return bar
end

local function accent() return ink("GREED") end

local function qualityColor(q)
    q = plain(q)
    if type(q) ~= "number" then return 1, 1, 1 end
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function classColor(class)
    class = plain(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return ink("VALUE")
end

local function classOf(name)
    local ok, _, token = pcall(UnitClass, name)
    return ok and plain(token) or nil
end

local function itemIdOf(link)
    link = plain(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function myName() return (UnitName("player")) end

-- The four choices, in the order they show.
local TYPES = {
    { key = "need",       roll = 1, tex = "Interface\\Buttons\\UI-GroupLoot-Dice", label = NEED or "Need" },
    { key = "greed",      roll = 2, tex = "Interface\\Buttons\\UI-GroupLoot-Coin", label = GREED or "Greed" },
    { key = "disenchant", roll = 3, tex = "Interface\\Buttons\\UI-GroupLoot-DE",   label = ROLL_DISENCHANT or "Disenchant" },
    { key = "pass",       roll = 0, tex = "Interface\\Buttons\\UI-GroupLoot-Pass", label = PASS or "Pass" },
}
local TYPE_BY_KEY = {}
for _, t in ipairs(TYPES) do TYPE_BY_KEY[t.key] = t end

local function typeIcon(key, size)
    local t = TYPE_BY_KEY[key]
    if not t then return "" end
    size = size or 14
    return ("|T%s-Up:%d:%d|t "):format(t.tex, size, size)
end

-- ---------------------------------------------------------------------
-- The bars

local DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 300 }

local anchor = CreateFrame("Frame", "TidyRollsAnchor", UIParent)
anchor:SetSize(WIDTH, ROW_HEIGHT)
anchor:SetScale(SCALE)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

local function placeAnchor()
    local p = (TidyRollsDB and TidyRollsDB.point) or DEFAULT_POINT
    anchor:ClearAllPoints()
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end
placeAnchor()

-- /tidyrolls unlock: a handle to drag.
local handle = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
handle:SetAllPoints()
handle:SetFrameStrata("DIALOG")
skin(handle)
-- No fill, just a soft gold outline, so the bars underneath look as they will.
handle:SetBackdropColor(0, 0, 0, 0)
handle:SetBackdropBorderColor(1, 0.82, 0, 0.6)
local handleText = text(handle, "small", "CENTER")
handleText:SetPoint("BOTTOM", handle, "TOP", 0, 4)   -- above the bars, not over them
handleText:SetTextColor(1, 0.82, 0)
handleText:SetText("Loot Rolls  (drag here, then /tidyrolls lock)")
-- The outline lets the mouse through, so the bars' tooltips still work;
-- the label above it is the grip you drag.
handle:EnableMouse(false)
local grip = CreateFrame("Frame", nil, handle)
grip:SetPoint("TOPLEFT", handleText, "TOPLEFT", -8, 4)
grip:SetPoint("BOTTOMRIGHT", handleText, "BOTTOMRIGHT", 8, -4)
grip:EnableMouse(true)
grip:RegisterForDrag("LeftButton")
grip:SetScript("OnEnter", function() SetCursor("UI_MOVE_CURSOR") end)
grip:SetScript("OnLeave", function() ResetCursor() end)
grip:SetScript("OnDragStart", function() anchor:StartMoving() end)
grip:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local p1, _, p2, x, y = anchor:GetPoint()
    TidyRollsDB = TidyRollsDB or {}
    TidyRollsDB.point = { p1, p2, math.floor(x + 0.5), math.floor(y + 0.5) }
end)
handle:Hide()

local rows = {}      -- the shown bars, oldest first
local byId = {}      -- roll id -> bar
local pool = {}
local dropRows = {}  -- modern loot history: drop key -> bar

local function layout()
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        local off = (i - 1) * (ROW_HEIGHT + GAP)
        if GROW_UP then
            row:SetPoint("BOTTOM", anchor, "BOTTOM", 0, off)
        else
            row:SetPoint("TOP", anchor, "TOP", 0, -off)
        end
    end
end

local function tooltipOwnedBy(row)
    return GameTooltip:IsOwned(row.icon) or GameTooltip:IsOwned(row.bar)
end

local function release(row)
    if tooltipOwnedBy(row) then GameTooltip:Hide() end
    row:Hide()
    if row.id ~= nil and byId[row.id] == row then byId[row.id] = nil end
    if row.dropKey and dropRows[row.dropKey] == row then dropRows[row.dropKey] = nil end
    for i, r in ipairs(rows) do
        if r == row then table.remove(rows, i) break end
    end
    pool[#pool + 1] = row
    layout()
end

-- The tooltip: the item, then who picked what.
local function showTooltip(row, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
    local shown = false
    if not row.test and not row.ended and row.id then
        shown = pcall(GameTooltip.SetLootRollItem, GameTooltip, row.id)
    end
    if not shown and row.link then
        pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
    end

    if next(row.players) then
        local groups = { need = {}, greed = {}, disenchant = {}, pass = {}, waiting = {} }
        for name, p in pairs(row.players) do
            local g = groups[p.type or "waiting"] or groups.waiting
            g[#g + 1] = name
        end
        local heads = {
            { "need",       TYPE_BY_KEY.need.label,       { ink("GOOD") } },
            { "greed",      TYPE_BY_KEY.greed.label,      { accent() } },
            { "disenchant", TYPE_BY_KEY.disenchant.label, { ink("LABEL") } },
            { "pass",       TYPE_BY_KEY.pass.label,       { ink("OFF") } },
            { "waiting",    "Waiting",                    { ink("OFF") } },
        }
        for _, h in ipairs(heads) do
            local list = groups[h[1]]
            if #list > 0 then
                table.sort(list)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(h[2], h[3][1], h[3][2], h[3][3])
                for _, name in ipairs(list) do
                    local p = row.players[name]
                    local r, g, b = classColor(p.class)
                    local text = "  " .. name
                    if p.roll then text = text .. "  (" .. p.roll .. ")" end
                    if p.winner then text = text .. "  - won" end
                    GameTooltip:AddLine(text, r, g, b)
                end
            end
        end
    end
    GameTooltip:Show()
end

local function refreshTooltip(row)
    if GameTooltip:IsOwned(row.icon) then showTooltip(row, row.icon)
    elseif GameTooltip:IsOwned(row.bar) then showTooltip(row, row.bar) end
end

-- Buttons: bright when you can pick them, dim when you can't, and once you
-- picked, only your pick stays bright.
local function paintButtons(row)
    for _, b in ipairs(row.buttons) do
        local tex = b:GetNormalTexture()
        if row.chosen then
            local mine = b.type.key == row.chosen
            b:SetAlpha(mine and 1 or 0.3)
            if tex then tex:SetDesaturated(not mine) end
        else
            b:SetAlpha(b.allowed and 1 or 0.3)
            if tex then tex:SetDesaturated(not b.allowed) end
        end
    end
end

local function refreshCounts(row)
    local n = { need = 0, greed = 0, disenchant = 0, pass = 0 }
    for _, p in pairs(row.players) do
        if p.type and n[p.type] then n[p.type] = n[p.type] + 1 end
    end
    for _, b in ipairs(row.buttons) do
        local c = n[b.type.key]
        b.count:SetText(c > 0 and c or "")
    end
end

local function addPlayer(row, name, class, key, roll, winner)
    if not name then return end
    local p = row.players[name]
    if not p then p = {}; row.players[name] = p end
    p.class = class or p.class or classOf(name)
    if key then p.type = key end
    if roll then p.roll = roll end
    if winner then p.winner = true end
    refreshCounts(row)
    refreshTooltip(row)
end

local function finish(row, text, r, g, b, stay)
    row.over, row.ended = true, true
    row.chosen = row.chosen or "none"
    paintButtons(row)
    row.bar:SetValue(0)
    row.status:SetText(text)
    row.status:SetTextColor(r, g, b)
    row.removeAt = GetTime() + stay
    refreshTooltip(row)
end

local function win(row, name)
    if row.over or not name then return end
    addPlayer(row, name, nil, nil, nil, true)
    local p = row.players[name]
    local r, g, b = classColor(p.class)
    finish(row, typeIcon(p.type) .. name, r, g, b, name == myName() and SHOW_WON or SHOW_LOST)
end

local function allPassed(row)
    if row.over then return end
    local r, g, b = ink("OFF")
    finish(row, "All passed", r, g, b, SHOW_LOST)
end

-- The roll ended for you (or you picked). Keep the bar a little while for
-- the winner; if nobody tells us, it just goes away.
local function ended(row)
    if row.ended then return end
    row.ended = true
    if not row.chosen then row.chosen = "none" end
    paintButtons(row)
    row.waitUntil = math.max(row.expires, GetTime()) + 3
end

local function onButton(self)
    local row = self:GetParent()
    if row.ended or not self.allowed then return end
    if not row.test then RollOnLoot(row.id, self.type.roll) end
    row.chosen = self.type.key
    paintButtons(row)
    if row.test then
        local _, token = UnitClass("player")
        addPlayer(row, myName(), token, self.type.key)
    end
    if HIDE_AFTER_ROLL then release(row) end
end

local function onButtonEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.type.label, 1, 1, 1)
    if not self.allowed and self.reason then
        local r, g, b = ink("BAD")
        GameTooltip:AddLine(self.reason, r, g, b, true)
    end
    GameTooltip:Show()
end

local function onUpdate(row, elapsed)
    row.tick = (row.tick or 0) + elapsed
    if row.tick < 0.1 then return end
    row.tick = 0
    local now = GetTime()
    if row.removeAt then
        if now >= row.removeAt then release(row) end
        return
    end
    local left = math.max(0, row.expires - now)
    row.bar:SetValue(row.length > 0 and left / row.length or 0)
    row.status:SetText(left > 0 and tostring(math.ceil(left)) or "")
    if row.test and left <= 0 then
        row.expires = now + row.length   -- sample bars keep running until you hide them
    elseif row.test and left <= 0 then
        -- A sample bar picks a winner from its sample players.
        local names = {}
        for name, p in pairs(row.players) do
            if p.type and p.type ~= "pass" then names[#names + 1] = name end
        end
        if #names > 0 then win(row, names[math.random(#names)]) else allPassed(row) end
    elseif row.ended and now > (row.waitUntil or 0) then
        release(row)
    elseif not row.test and not row.ended and left <= 0 then
        ended(row)   -- time ran out without the game saying so
    end
end

-- The game's rounded icon mask (the action bar's). Only used when this
-- client has it, so a missing one can never blank the icon.
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local function hasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A rounded border in the item's quality color around the icon, the icon's
-- corners cut to match.
local function makeRoundBorder(frame)
    if hasAtlas(ICON_MASK) then
        local mask = frame:CreateMaskTexture()
        mask:SetAtlas(ICON_MASK, false)
        mask:SetAllPoints(frame.tex)
        frame.tex:AddMaskTexture(mask)
    end
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({ edgeFile = ROUND_EDGE, edgeSize = 8 })
    -- The BoP tag and count go above the border.
    local top = CreateFrame("Frame", nil, frame)
    top:SetAllPoints()
    top:SetFrameLevel(border:GetFrameLevel() + 1)
    frame.textLayer = top
    return function(r, g, b) border:SetBackdropBorderColor(r, g, b, 1) end
end

-- A thin border in the item's quality color around the icon.
local function makeBorder(frame)
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT", -1, 1);    edges[1]:SetPoint("TOPRIGHT", 1, 1);       edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", -1, -1); edges[2]:SetPoint("BOTTOMRIGHT", 1, -1);  edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", -1, 1);    edges[3]:SetPoint("BOTTOMLEFT", -1, -1);   edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", 1, 1);    edges[4]:SetPoint("BOTTOMRIGHT", 1, -1);   edges[4]:SetWidth(1)
    return function(r, g, b) for _, t in ipairs(edges) do t:SetVertexColor(r, g, b) end end
end

local function makeRow()
    local row = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    row:SetSize(WIDTH, ROW_HEIGHT)
    skin(row)

    local size = ROW_HEIGHT - 8
    local icon = CreateFrame("Button", nil, row)
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", 5, 0)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.setBorder = ROUND_ICON and makeRoundBorder(icon) or makeBorder(icon)
    local layer = icon.textLayer or icon
    icon.bop = text(layer, "tiny", "CENTER")
    icon.bop:SetPoint("BOTTOM", 0, 1)
    icon.bop:SetText("BoP")
    icon.count = text(layer, "tiny", "RIGHT")
    icon.count:SetPoint("TOPRIGHT", 0, -1)
    icon:SetScript("OnEnter", function(self) showTooltip(row, self) end)
    icon:SetScript("OnLeave", GameTooltip_Hide)
    icon:SetScript("OnClick", function()
        if row.link and HandleModifiedItemClick then HandleModifiedItemClick(row.link) end
    end)
    row.icon = icon

    row.buttons = {}
    local prev, btnSize = icon, ROW_HEIGHT - 8
    local shownTypes = {}
    for _, t in ipairs(TYPES) do
        if t.key ~= "disenchant" or SHOW_DISENCHANT then shownTypes[#shownTypes + 1] = t end
    end
    for i, t in ipairs(shownTypes) do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(btnSize, btnSize)
        b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 7 or 3, 0)
        b:SetNormalTexture(t.tex .. "-Up")
        b:SetPushedTexture(t.tex .. "-Down")
        b:SetHighlightTexture(t.tex .. "-Highlight", "ADD")
        b.type = t
        b.count = text(b, "tiny", "RIGHT")
        b.count:SetPoint("BOTTOMRIGHT", 3, -2)
        b:SetScript("OnClick", onButton)
        b:SetScript("OnEnter", onButtonEnter)
        b:SetScript("OnLeave", GameTooltip_Hide)
        row.buttons[i] = b
        prev = b
    end

    local bar = makeBar(row)
    bar.holder:SetPoint("LEFT", prev, "RIGHT", 7, 0)
    bar.holder:SetPoint("RIGHT", -6, 0)
    bar.holder:SetHeight(ROW_HEIGHT - 12)
    bar:SetMinMaxValues(0, 1)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self) showTooltip(row, self) end)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    row.bar = bar

    row.status = text(bar, "small", "RIGHT")
    row.status:SetPoint("RIGHT", -4, 0)
    row.name = text(bar, "small", "LEFT")
    row.name:SetPoint("LEFT", 5, 0)
    row.name:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.name:SetWordWrap(false)

    row:SetScript("OnUpdate", onUpdate)
    return row
end

local function acquire()
    local row = table.remove(pool) or makeRow()
    row.id, row.test, row.link, row.itemID, row.dropKey = nil, nil, nil, nil, nil
    row.chosen, row.ended, row.over, row.removeAt, row.waitUntil = nil, nil, nil, nil, nil
    row.players = {}
    row.tick = 1
    for _, b in ipairs(row.buttons) do b.count:SetText("") end
    return row
end

-- Fill a bar and show it. can/why: per choice, may you pick it and why not.
local function show(row, tex, name, count, quality, bop, can, why)
    row.icon.tex:SetTexture(tex)
    local r, g, b = qualityColor(quality)
    row.icon.setBorder(r, g, b)
    row.name:SetText(name)
    row.name:SetTextColor(r, g, b)
    row.bar:SetStatusBarColor(r * 0.45, g * 0.45, b * 0.45, 0.9)
    local n = plain(count)
    row.icon.count:SetText(type(n) == "number" and n > 1 and n or "")
    row.icon.bop:SetShown(plain(bop) and true or false)
    row.icon.bop:SetTextColor(ink("BAD"))
    row.status:SetTextColor(ink("VALUE"))
    for _, btn in ipairs(row.buttons) do
        local key, v = btn.type.key, can[btn.type.key]
        -- A value we can't read: let the game decide when it's clicked.
        btn.allowed = key == "pass" or issecret(v) or (v and true or false)
        local reason = plain(why[key])
        btn.reason = reason and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason] or nil
    end
    paintButtons(row)
    rows[#rows + 1] = row
    layout()
    row:Show()
end

-- ---------------------------------------------------------------------
-- Real rolls

local waitingItem = {}

local function start(id, ms, length)
    id, ms = plain(id), plain(ms)
    if not id or byId[id] then return end
    ms = ms or 60000
    local tex, name, count, quality, bop, canNeed, canGreed, canDE, whyNeed, whyGreed, whyDE = GetLootRollItemInfo(id)
    if not issecret(name) and name == nil then
        -- The item isn't loaded yet: try again once it is.
        local itemID = itemIdOf(GetLootRollItemLink(id))
        if itemID and Item and not waitingItem[id] then
            waitingItem[id] = true
            Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                waitingItem[id] = nil
                local left = plain(GetLootRollTimeLeft(id))
                if left and left > 0 then start(id, left, length or ms / 1000) end
            end)
        end
        return
    end
    local row = acquire()
    row.id = id
    row.link = plain(GetLootRollItemLink(id))
    row.itemID = itemIdOf(row.link)
    local left = ms / 1000
    row.expires = GetTime() + left
    row.length = math.max(left, length or left)
    byId[id] = row
    show(row, tex, name, count, quality, bop,
        { need = canNeed, greed = canGreed, disenchant = canDE },
        { need = whyNeed, greed = whyGreed, disenchant = whyDE })
end

local function rowForLink(link)
    local want = itemIdOf(link)
    if not want then return nil end
    for _, row in ipairs(rows) do
        if not row.test and not row.over and row.itemID == want then return row end
    end
end

-- Who picked what, from the game's loot history (older clients).
local History = C_LootHistory
local CLASSIC_TYPE = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "disenchant" }
local hasClassicHistory = History and History.GetItem and History.GetPlayerInfo and true or false
local hasDropHistory = History and History.GetSortedInfoForDrop and true or false

local function fromHistory(hid)
    local rollID, _, numPlayers, isDone = History.GetItem(hid)
    local row = plain(rollID) and byId[plain(rollID)]
    if not row or row.over then return end
    local winner
    for p = 1, plain(numPlayers) or 0 do
        local name, class, rtype, roll, isWinner = History.GetPlayerInfo(hid, p)
        name = plain(name)
        if name then
            addPlayer(row, name, plain(class), CLASSIC_TYPE[plain(rtype)], plain(roll))
            if plain(isWinner) then winner = name end
        end
    end
    if plain(isDone) then
        if winner then win(row, winner) else allPassed(row) end
    end
end

local function allHistory()
    local seen, hid = {}, 1
    while true do
        local rollID = History.GetItem(hid)
        if rollID == nil then return end
        rollID = plain(rollID)
        -- Newest first: only the first entry for an id is the current roll.
        if rollID and not seen[rollID] then
            seen[rollID] = true
            if byId[rollID] then fromHistory(hid) end
        end
        hid = hid + 1
    end
end

-- Who picked what, from the game's loot history (newer clients).
local DROP_TYPE = {}
do
    local S = Enum and Enum.EncounterLootDropRollState
    if S then
        if S.NeedMainSpec then DROP_TYPE[S.NeedMainSpec] = "need" end
        if S.NeedOffSpec then DROP_TYPE[S.NeedOffSpec] = "need" end
        if S.Transmog then DROP_TYPE[S.Transmog] = "greed" end
        if S.Greed then DROP_TYPE[S.Greed] = "greed" end
        if S.Pass then DROP_TYPE[S.Pass] = "pass" end
    end
end

local function fromDrop(encounterID, lootListID)
    encounterID, lootListID = plain(encounterID), plain(lootListID)
    if not encounterID or not lootListID then return end
    local drop = History.GetSortedInfoForDrop(encounterID, lootListID)
    if type(drop) ~= "table" then return end
    local key = encounterID .. ":" .. lootListID
    local row = dropRows[key]
    if row and (row.dropKey ~= key or not row:IsShown()) then row, dropRows[key] = nil, nil end
    if not row then
        local want = itemIdOf(drop.itemHyperlink)
        if not want then return end
        for _, r in ipairs(rows) do
            if not r.test and not r.dropKey and not r.over and r.itemID == want then row = r break end
        end
        if not row then return end
        row.dropKey, dropRows[key] = key, row
    end
    if row.over then return end
    for _, info in ipairs(drop.rollInfos or {}) do
        local name = plain(info.playerName)
        if name then addPlayer(row, name, plain(info.playerClass), DROP_TYPE[plain(info.state)], plain(info.roll)) end
    end
    local w = drop.winner
    if type(w) == "table" and plain(w.playerName) then
        win(row, plain(w.playerName))
    elseif plain(drop.allPassed) then
        allPassed(row)
    end
end

-- Who picked what, from the chat lines (when the game has no loot history).
local CHAT = {}
local function toPattern(fmt)
    local p = fmt:gsub("%%%d*%$?s", "\1"):gsub("%%%d*%$?d", "\2")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end
local function chatLine(global, kind, order)
    local fmt = _G[global]
    if type(fmt) == "string" then CHAT[#CHAT + 1] = { pat = toPattern(fmt), kind = kind, order = order } end
end
-- Lines about you and about everyone first: "You won" would also read as "<name> won".
chatLine("LOOT_ROLL_ALL_PASSED", "allpassed", "l")
chatLine("LOOT_ROLL_YOU_WON", "won", "l")
chatLine("LOOT_ROLL_NEED_SELF", "need", "l")
chatLine("LOOT_ROLL_GREED_SELF", "greed", "l")
chatLine("LOOT_ROLL_DISENCHANT_SELF", "disenchant", "l")
chatLine("LOOT_ROLL_PASSED_SELF", "pass", "l")
chatLine("LOOT_ROLL_PASSED_SELF_AUTO", "pass", "l")
chatLine("LOOT_ROLL_ROLLED_NEED", "need", "rln")
chatLine("LOOT_ROLL_ROLLED_GREED", "greed", "rln")
chatLine("LOOT_ROLL_ROLLED_DE", "disenchant", "rln")
chatLine("LOOT_ROLL_NEED", "need", "nl")
chatLine("LOOT_ROLL_GREED", "greed", "nl")
chatLine("LOOT_ROLL_DISENCHANT", "disenchant", "nl")
chatLine("LOOT_ROLL_PASSED", "pass", "nl")
chatLine("LOOT_ROLL_PASSED_AUTO", "pass", "nl")
chatLine("LOOT_ROLL_PASSED_AUTO_FEMALE", "pass", "nl")
chatLine("LOOT_ROLL_WON", "won", "nl")

local function fromChat(msg)
    if issecret(msg) or type(msg) ~= "string" then return end
    for _, c in ipairs(CHAT) do
        local a, b, d = msg:match(c.pat)
        if a then
            local name, link, roll
            if c.order == "nl" then name, link = a, b
            elseif c.order == "l" then name, link = myName(), a
            else roll, link, name = tonumber(a), b, d end
            local row = rowForLink(link)
            if not row then return end
            if c.kind == "won" then win(row, name)
            elseif c.kind == "allpassed" then allPassed(row)
            else addPlayer(row, name, nil, c.kind, roll) end
            return
        end
    end
end

-- ---------------------------------------------------------------------
-- Sample bars (/tidyrolls)

local SAMPLE_ITEMS = { 4338, 7048, 873, 2163 }   -- Mageweave Cloth, Azure Silk Hood, Staff of Jordan, Shadowblade
local SAMPLE_PLAYERS = {
    { "Aldric", "WARRIOR" }, { "Brisa", "PRIEST" }, { "Corvin", "ROGUE" }, { "Dalia", "MAGE" },
}
local nextSampleId = -1

local function clearSamples()
    for i = #rows, 1, -1 do
        if rows[i].test then release(rows[i]) end
    end
end

local function showSample(itemID, index)
    local item = Item and Item:CreateFromItemID(itemID)
    if not item or item:IsItemEmpty() then return end
    item:ContinueOnItemLoad(function()
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local name, link, quality, _, _, _, _, _, _, tex = getInfo(itemID)
        if not name then return end
        local row = acquire()
        row.id, row.test, row.link, row.itemID = nextSampleId, true, link, itemID
        nextSampleId = nextSampleId - 1
        row.length = 60
        row.expires = GetTime() + 20 + index * 8
        byId[row.id] = row
        show(row, tex, name, 1, quality, quality >= 3,
            { need = index ~= 1, greed = true, disenchant = quality >= 2 },
            { need = index == 1 and 1 or nil, disenchant = quality < 2 and 4 or nil })
        local picks = { "need", "greed", "pass", "greed" }
        for i, p in ipairs(SAMPLE_PLAYERS) do
            if (i + index) % 3 ~= 0 then
                addPlayer(row, p[1], p[2], picks[(i + index) % 4 + 1], math.random(1, 100))
            end
        end
    end)
end

local function showSamples()
    clearSamples()
    for i, id in ipairs(SAMPLE_ITEMS) do showSample(id, i) end
end

local function toggleSamples()
    for _, r in ipairs(rows) do
        if r.test then clearSamples() return end
    end
    showSamples()
end

SLASH_TIDYROLLS1 = "/tidyrolls"
SlashCmdList.TIDYROLLS = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "unlock" then
        -- The drag box covers all the sample bars, so you see where they'll sit.
        local n = #SAMPLE_ITEMS
        handle:ClearAllPoints()
        handle:SetPoint(GROW_UP and "BOTTOMLEFT" or "TOPLEFT")
        handle:SetSize(WIDTH, n * ROW_HEIGHT + (n - 1) * GAP)
        handle:Show()
        showSamples()
        print("|cffffd100Tidy Roll|r: drag the gold label above the bars, then type /tidyrolls lock.")
    elseif msg == "lock" then
        handle:Hide()
        clearSamples()
    elseif msg == "reset" then
        TidyRollsDB = TidyRollsDB or {}
        TidyRollsDB.point = nil
        placeAnchor()
    else
        toggleSamples()
    end
end

-- ---------------------------------------------------------------------
-- Taking over from the game's own roll frames

local hookedDefault = {}
local function hideDefault(f)
    f:Hide()
    if GroupLootContainer and GroupLootContainer_RemoveFrame then
        pcall(GroupLootContainer_RemoveFrame, GroupLootContainer, f)
    end
end

local function suppressDefault()
    UIParent:UnregisterEvent("START_LOOT_ROLL")
    UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local f = _G["GroupLootFrame" .. i]
        if f then
            f:UnregisterAllEvents()
            hideDefault(f)
            if not hookedDefault[f] then
                hookedDefault[f] = true
                hooksecurefunc(f, "Show", hideDefault)
            end
        end
    end
end

local function resume()
    if not GetActiveLootRollIDs then return end
    for _, id in ipairs(GetActiveLootRollIDs() or {}) do
        local left = plain(GetLootRollTimeLeft(id))
        if left and left > 0 then start(id, left, 60) end
    end
end

local events = CreateFrame("Frame")
local handlers = {}

function handlers.PLAYER_LOGIN()
    TidyRollsDB = TidyRollsDB or {}
    placeAnchor()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("XLoot_Group") then
        print("|cffffd100Tidy Roll|r: XLoot Group is on too, so Tidy Roll stays off. Turn one of them off.")
        return
    end
    suppressDefault()
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("START_LOOT_ROLL")
    pcall(events.RegisterEvent, events, "CANCEL_LOOT_ROLL")
    pcall(events.RegisterEvent, events, "CANCEL_ALL_LOOT_ROLLS")
    if hasDropHistory then
        pcall(events.RegisterEvent, events, "LOOT_HISTORY_UPDATE_DROP")
    elseif hasClassicHistory then
        pcall(events.RegisterEvent, events, "LOOT_HISTORY_ROLL_CHANGED")
        pcall(events.RegisterEvent, events, "LOOT_HISTORY_ROLL_COMPLETE")
        pcall(events.RegisterEvent, events, "LOOT_ROLLS_COMPLETE")
    else
        events:RegisterEvent("CHAT_MSG_LOOT")
    end
    resume()
end

function handlers.PLAYER_ENTERING_WORLD()
    suppressDefault()
    resume()
end

function handlers.START_LOOT_ROLL(id, ms) start(id, ms) end

function handlers.CANCEL_LOOT_ROLL(id)
    local row = plain(id) and byId[plain(id)]
    if row and not row.test then ended(row) end
end

function handlers.CANCEL_ALL_LOOT_ROLLS()
    for i = #rows, 1, -1 do
        if not rows[i].test then release(rows[i]) end
    end
end

function handlers.LOOT_HISTORY_UPDATE_DROP(encounterID, lootListID) fromDrop(encounterID, lootListID) end
function handlers.LOOT_HISTORY_ROLL_CHANGED(hid) if plain(hid) then fromHistory(hid) end end
handlers.LOOT_HISTORY_ROLL_COMPLETE = allHistory
handlers.LOOT_ROLLS_COMPLETE = allHistory
function handlers.CHAT_MSG_LOOT(msg) fromChat(msg) end

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)
