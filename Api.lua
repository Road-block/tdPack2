-- Api.lua
-- @Author : Dencer (tdaddon@163.com)
-- @Link   : https://dengsir.github.io
-- @Date   : 8/30/2019, 11:46:11 PM
--
---@class ns
---@field UI UI
---@field Base Base
---@field Item _Item
---@field Bag Bag
---@field Slot Slot
---@field Group Group
---@field Pack Pack
---@field Rule Rule
---@field Order Order
---@field Task Task
---@field CachableOrder CachableOrder
---@field CustomOrder CustomOrder
---@field ItemInfoCache ItemInfoCache
---@field Saving Saving
---@field Stacking Stacking
---@field Sorting Sorting
---@field Search Search
local ns = select(2, ...)

---- LUA
local select, type, assert, ipairs = select, type, assert, ipairs
local tostring, format, strrep = tostring, string.format, string.rep
local tonumber, band = tonumber, bit.band

---- WOW
local GetContainerItemInfo = function(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
        end
    else
        return _G.GetContainerItemInfo(bag, slot)
    end
end
local GetContainerItemID = GetContainerItemID or C_Container.GetContainerItemID
local GetContainerItemLink = GetContainerItemLink or C_Container.GetContainerItemLink
local GetContainerNumFreeSlots = GetContainerNumFreeSlots or C_Container.GetContainerNumFreeSlots
local GetContainerNumSlots = GetContainerNumSlots or C_Container.GetContainerNumSlots
local ContainerIDToInventoryID = ContainerIDToInventoryID or C_Container.ContainerIDToInventoryID
local PickupContainerItem = PickupContainerItem or C_Container.PickupContainerItem
local GetCursorPosition = GetCursorPosition
local GetItemFamily = GetItemFamily
local GetItemIcon = GetItemIcon
local GetItemInfoInstant = GetItemInfoInstant
local GetItemQualityColor = GetItemQualityColor

---- UI
local UIParent = UIParent

ns.VERSION = tonumber((GetAddOnMetadata('tdPack2', 'Version'):gsub('(%d+)%.?', function(x)
    return format('%02d', tonumber(x))
end))) or 0

---- ENUM
ns.BAG_TYPE = {
    BAG = 'bag', --
    BANK = 'bank', --
}

ns.BAG_TYPES = {
    ns.BAG_TYPE.BAG, --
    ns.BAG_TYPE.BANK, --
}

ns.COMMAND = {
    ALL = 'all', --
    BAG = 'bag', --
    BANK = 'bank', --
}

ns.EXTRA_COMMAND = {
    SAVE = 'save', --
}

ns.ORDER = {
    ASC = 'asc', --
    DESC = 'desc', --
}

ns.SORT_TYPE = {
    SORTING = 1, --
    SAVING = 2, --
}

local function riter(t, i)
    i = i - 1
    if i > 0 then
        return i, t[i]
    end
end

---@generic T
---@param t T[]
---@return fun(): number, T
function ns.ripairs(t)
    assert(type(t) == 'table')

    return riter, t, #t + 1
end

function ns.memorize(func)
    local cache = {}
    return function(arg1, ...)
        local value = cache[arg1]
        if value == nil then
            value = func(arg1, ...)
            cache[arg1] = value
        end
        return value
    end
end

local BAGS = { --
    [ns.BAG_TYPE.BAG] = {BACKPACK_CONTAINER},
    [ns.BAG_TYPE.BANK] = {BANK_CONTAINER},
}
local BAG_SETS = {}

do
    for i = 1, NUM_BAG_SLOTS do
        tinsert(BAGS[ns.BAG_TYPE.BAG], i)
    end

    for i = 1, NUM_BANKBAGSLOTS do
        tinsert(BAGS[ns.BAG_TYPE.BANK], i + NUM_BAG_SLOTS)
    end

    tinsert(BAGS[ns.BAG_TYPE.BAG], KEYRING_CONTAINER)

    for bagType, v in pairs(BAGS) do
        for _, bagId in pairs(v) do
            BAG_SETS[bagId] = bagType
        end
    end
end

function ns.IsBag(id)
    return BAG_SETS[id] == ns.BAG_TYPE.BAG
end

function ns.IsBank(id)
    return BAG_SETS[id] == ns.BAG_TYPE.BANK
end

function ns.GetBags(bagType)
    return BAGS[bagType]
end

function ns.GetItemFamily(itemId)
    if not itemId then
        return 0
    end
    if type(itemId) == 'string' then
        return 0
    end
    if select(4, GetItemInfoInstant(itemId)) == 'INVTYPE_BAG' then
        return 0
    end
    local itemFamily = GetItemFamily(itemId)
    return itemFamily
end

function ns.GetBagFamily(bag)
    -- @build<2@
    if bag == KEYRING_CONTAINER then
        return 9
    end
    -- @end-build<2@
    -- @build>2@
    if bag == KEYRING_CONTAINER then
        return 256
    end
    -- @end-build<2@

    -- 3.4 GetContainerNumFreeSlots 接口有bug，专业包可能取到0
    if bag > 0 then
        local invId = ContainerIDToInventoryID(bag)
        local itemId = GetInventoryItemID('player', invId)
        if itemId then
            local itemFamily = GetItemFamily(itemId)
            if itemFamily then
                return itemFamily
            end
            return nil
        else
            return 0
        end
    end

    return select(2, GetContainerNumFreeSlots(bag))
end

function ns.GetBagNumSlots(bag)
    return GetContainerNumSlots(bag)
end

function ns.GetItemId(itemLink)
    if not itemLink then
        return
    end

    if itemLink:find('battlepet') then
        local id, level, quality = itemLink:match('battlepet:(%d+):(%d+):(%d+)')

        return (('battlepet:%d:%d:%d'):format(id, level, quality))
    else
        return (tonumber(itemLink:match('item:(%d+)')))
    end
end

function ns.GetBagSlotLink(bag, slot)
    return GetContainerItemLink(bag, slot)
end

function ns.GetBagSlotId(bag, slot)
    local itemLink = GetContainerItemLink(bag, slot)
    if not itemLink then
        return
    end
    return ns.GetItemId(itemLink)
end

function ns.IsBagSlotEmpty(bag, slot)
    return not GetContainerItemID(bag, slot)
end

function ns.IsBagSlotFull(bag, slot)
    local itemId = GetContainerItemID(bag, slot)
    if not itemId then
        return false
    end

    local info = ns.ItemInfoCache:Get(itemId)
    local stackCount = info.itemStackCount or 1
    return stackCount == 1 or stackCount == ns.GetBagSlotCount(bag, slot)
end

function ns.GetBagSlotCount(bag, slot)
    return (select(2, GetContainerItemInfo(bag, slot)))
end

function ns.GetBagSlotFamily(bag, slot)
    return ns.GetItemFamily(ns.GetBagSlotId(bag, slot))
end

function ns.IsBagSlotLocked(bag, slot)
    return (select(3, GetContainerItemInfo(bag, slot)))
end

function ns.PickupBagSlot(bag, slot)
    return PickupContainerItem(bag, slot)
end

-- @build<2@
function ns.IsFamilyContains(bagFamily, itemFamily)
    return bagFamily == itemFamily
end
-- @end-build<2@

-- @build>2@
function ns.IsFamilyContains(bagFamily, itemFamily)
    return band(bagFamily, itemFamily) > 0
end
-- @end-build>2@

function ns.GetClickToken(button, control, shift, alt)
    local key
    if button == 'LeftButton' then
        key = 1
    elseif button == 'RightButton' then
        key = 2
    end

    return key + (control and 0x10000 or 0) + (shift and 0x20000 or 0) + (alt and 0x40000 or 0)
end

function ns.GetCursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetScale()
    return x / scale, y / scale
end

function ns.CopyFrom(dest, src)
    dest = dest or {}
    for k, v in pairs(src) do
        if type(v) == 'table' then
            dest[k] = ns.CopyFrom({}, v)
        else
            dest[k] = v
        end
    end
    return dest
end

function ns.GetRuleInfo(item)
    local t = type(item)
    if t == 'number' then
        local name, color
        local icon = GetItemIcon(item)
        local info = ns.ItemInfoCache:Get(item)
        if info:IsReady() then
            name = info.itemName
            color = select(4, GetItemQualityColor(info.itemQuality))
        else
            name = RETRIEVING_ITEM_INFO
            color = RED_FONT_COLOR:GenerateHexColor()
        end
        return format('|c%s%s|r', color, name), icon
    elseif t == 'table' then
        local name, rule
        if item.comment then
            name = item.comment
            rule = item.rule
        else
            name = item.rule
            rule = item.rule
        end
        return name, item.icon or ns.UNKNOWN_ICON, rule, item.children and #item.children > 0
    end
end

function ns.IsAdvanceRule(item)
    return type(item) == 'table'
end

local function Initialize(_, level, menuList)
    for i, v in ipairs(menuList) do
        if v.isSeparator then
            UIDropDownMenu_AddSeparator(level)
        elseif v.text then
            v.index = i;
            UIDropDownMenu_AddButton(v, level);
        end
    end
end

local function CreateGlobalMenuFrame()
    local menuFrame = CreateFrame('Frame', 'tdGlobalMenuFrame', UIParent, 'UIDropDownMenuTemplate')
    menuFrame.initialize = Initialize
    menuFrame.displayMode = 'MENU'
    return menuFrame
end

function ns.ToggleMenu(owner, menuList)
    local menuFrame = tdGlobalMenuFrame or CreateGlobalMenuFrame()

    if DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menuFrame and menuFrame.LastOwner == owner then
        CloseDropDownMenus()
    else
        menuFrame.LastOwner = owner
        CloseDropDownMenus()
        ToggleDropDownMenu(1, nil, menuFrame, owner, 0, 0, menuList)
    end
end
