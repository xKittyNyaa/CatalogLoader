-- Catalog Loader V2
-- Browse the Marketplace with the same filters as the website, or paste an ID / link, and import items.
-- With NPCs (models with a Humanoid) selected, wearable items are put on every selected NPC.
-- Saved NPCs are stored in this plugin's settings, so they show up in every place opened in Studio.

local RunService = game:GetService("RunService")
if not RunService:IsEdit() then
	return
end

-- Bump this with every release pushed to GitHub: the Update button compares it with this file there.
local VERSION = "2.0.3"
local UPDATE_URL = "https://raw.githubusercontent.com/xKittyNyaa/CatalogLoader/main/CatalogLoader.lua"
local UPDATE_SETTINGS = { version = "UpdateVersion", source = "UpdateSource" }

-- True when version string a ("2.0.3") is newer than b ("2.0.2").
local function isNewerVersion(a, b)
	local x = { string.match(tostring(a), "^(%d+)%.(%d+)%.(%d+)$") }
	local y = { string.match(tostring(b), "^(%d+)%.(%d+)%.(%d+)$") }
	if #x < 3 or #y < 3 then
		return false
	end
	for i = 1, 3 do
		local p, q = tonumber(x[i]), tonumber(y[i])
		if p ~= q then
			return p > q
		end
	end
	return false
end

-- Turns downloaded plugin source into a function that runs it as this plugin. Plugins can't write to
-- the Plugins folder, so updates are kept in plugin settings and loaded through a ModuleScript.
local function compileUpdate(source)
	local module = Instance.new("ModuleScript")
	module.Name = "CatalogLoaderUpdate"
	local ok, result = pcall(function()
		module.Source = "return function(plugin)\n" .. source .. "\nend"
		return require(module)
	end)
	module:Destroy()
	if ok and type(result) == "function" then
		return result
	end
	return nil, ok and "the update didn't load" or result
end

-- A downloaded update newer than this file runs instead of it; one that's not newer (because this
-- file was replaced with a newer copy) is cleared.
do
	local storedVersion = plugin:GetSetting(UPDATE_SETTINGS.version)
	if storedVersion and storedVersion ~= VERSION then
		if isNewerVersion(storedVersion, VERSION) then
			local run, err = compileUpdate(plugin:GetSetting(UPDATE_SETTINGS.source) or "")
			if run then
				run(plugin)
				return
			end
			warn("[Catalog Loader V2] Couldn't start the downloaded update, using V" .. VERSION .. ":", err)
		else
			plugin:SetSetting(UPDATE_SETTINGS.version, nil)
			plugin:SetSetting(UPDATE_SETTINGS.source, nil)
		end
	end
end

local AvatarEditorService = game:GetService("AvatarEditorService")
local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")
local EncodingService = game:GetService("EncodingService")
local CoreGui = game:GetService("CoreGui")

local GUI_NAME = "CatalogLoaderV2Gui"
local DEFAULT_W, DEFAULT_H = 900, 720
local MIN_W, MIN_H = 760, 480
local TITLE_H = 40
local PAGE_LIMIT = 60
local BOTTOM_AREA = 80 -- status line + bottom bar
local LEFT_BUTTONS_W = 222 -- Folders + Spawn NPC
local RIGHT_BUTTONS_W = 216 -- gap + Import + gap + Fix NPC, to the right of the ID box
local SIDE_W, SIDE_GAP = 400, 6
-- Loaded through the thumbnail service: a plain rbxassetid image owned by a person won't load in
-- group-owned places, but its thumbnail loads everywhere.
local ICON = "rbxthumb://type=Asset&id=136699811200889&w=150&h=150"
local MAX_TRANSPARENCY = 0.8 -- the UI never fades out completely

-- "Spawn NPC" clones the chosen gender's rig from the place: the path is tried first, then any rig
-- with one of these names. Places without one use the copy built into the plugin.
local TEMPLATE_RIGS = {
	female = { path = { "Template" }, names = { "Template", "Template Rig" } },
	male = { path = { "Template2" }, names = { "Template2" } },
}
local LABEL_NAME = "NPC Label"

local SETTING = {
	theme = "Theme",
	customTheme = "CustomTheme", -- single custom theme from the previous version
	customThemes = "CustomThemes",
	transparency = "UITransparency",
	spawnWithLabel = "SpawnWithLabel",
	spawnTemplate = "SpawnTemplate", -- stored template from the previous version, cleared on load
	spawnTemplateName = "SpawnTemplateName",
	panelPosition = "PanelPosition",
	savedIndex = "SavedNPCIndex",
	savedNpcPrefix = "SavedNPC_",
	poses = "NPCPoses",
}

-- Functions shared between sections. Sections are do-blocks to stay under Luau's 200-locals limit.
local api = {}

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------

local THEMES, FIXED_COLORS, deriveTheme, luminance
do
	local function rgb(r, g, b)
		return Color3.fromRGB(r, g, b)
	end

	THEMES = {
		{ name = "Classic", colors = {
			panel = rgb(40, 40, 43), header = rgb(30, 30, 33), input = rgb(28, 28, 30), popup = rgb(48, 48, 52),
			cell = rgb(52, 52, 56), cellHover = rgb(66, 66, 72), stroke = rgb(70, 70, 76), buttonHover = rgb(60, 60, 66),
			text = rgb(235, 235, 238), subtext = rgb(165, 165, 172), accent = rgb(0, 145, 255), accentHover = rgb(40, 165, 255),
		} },
		{ name = "Sakura Pink", colors = {
			panel = rgb(58, 36, 50), header = rgb(44, 26, 38), input = rgb(38, 22, 33), popup = rgb(68, 42, 58),
			cell = rgb(74, 46, 64), cellHover = rgb(92, 58, 80), stroke = rgb(110, 70, 96), buttonHover = rgb(86, 54, 74),
			text = rgb(255, 240, 248), subtext = rgb(222, 170, 200), accent = rgb(255, 105, 180), accentHover = rgb(255, 140, 198),
		} },
		{ name = "Ocean Blue", colors = {
			panel = rgb(26, 38, 60), header = rgb(18, 28, 46), input = rgb(15, 23, 39), popup = rgb(32, 47, 73),
			cell = rgb(36, 52, 80), cellHover = rgb(46, 66, 100), stroke = rgb(58, 82, 120), buttonHover = rgb(42, 60, 92),
			text = rgb(236, 244, 255), subtext = rgb(160, 185, 220), accent = rgb(30, 144, 255), accentHover = rgb(80, 170, 255),
		} },
		{ name = "Royal Purple", colors = {
			panel = rgb(42, 30, 62), header = rgb(31, 21, 48), input = rgb(26, 18, 40), popup = rgb(52, 38, 76),
			cell = rgb(58, 42, 84), cellHover = rgb(74, 54, 106), stroke = rgb(92, 68, 130), buttonHover = rgb(66, 48, 96),
			text = rgb(244, 238, 255), subtext = rgb(190, 170, 225), accent = rgb(155, 89, 255), accentHover = rgb(180, 125, 255),
		} },
		{ name = "Mint Garden", colors = {
			panel = rgb(24, 44, 40), header = rgb(17, 33, 30), input = rgb(14, 28, 25), popup = rgb(30, 54, 49),
			cell = rgb(34, 60, 54), cellHover = rgb(44, 77, 69), stroke = rgb(56, 96, 86), buttonHover = rgb(40, 70, 63),
			text = rgb(236, 255, 248), subtext = rgb(160, 210, 195), accent = rgb(24, 178, 122), accentHover = rgb(52, 204, 148),
		} },
		{ name = "Sunset", colors = {
			panel = rgb(54, 34, 30), header = rgb(41, 25, 22), input = rgb(34, 20, 18), popup = rgb(64, 41, 36),
			cell = rgb(70, 45, 39), cellHover = rgb(88, 57, 49), stroke = rgb(110, 72, 60), buttonHover = rgb(82, 52, 45),
			text = rgb(255, 244, 236), subtext = rgb(226, 180, 160), accent = rgb(240, 110, 50), accentHover = rgb(255, 140, 90),
		} },
		{ name = "Cherry Blossom", cherry = true, colors = {
			panel = rgb(255, 183, 197), header = rgb(246, 158, 179), input = rgb(255, 228, 235), popup = rgb(255, 204, 215),
			cell = rgb(255, 214, 223), cellHover = rgb(255, 230, 236), stroke = rgb(222, 120, 150), buttonHover = rgb(255, 221, 229),
			text = rgb(255, 255, 255), subtext = rgb(255, 240, 245), accent = rgb(228, 70, 126), accentHover = rgb(240, 108, 154),
		}, textStroke = rgb(178, 62, 106) },
	}

	FIXED_COLORS = {
		good = rgb(70, 185, 105),
		bad = rgb(235, 90, 90),
		closeHover = rgb(200, 55, 55),
	}

	function luminance(color)
		return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	end

	-- Builds a full palette from the three colors chosen in the custom theme picker.
	function deriveTheme(bg, accent, text)
		local white, black = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
		local light = luminance(bg) > 0.55
		local function shade(amount) -- positive lightens, negative darkens
			return amount >= 0 and bg:Lerp(white, amount) or bg:Lerp(black, -amount)
		end
		return { name = "Custom", colors = {
			panel = bg,
			header = shade(-0.18),
			input = shade(light and 0.45 or -0.3),
			popup = shade(light and 0.2 or 0.08),
			cell = shade(light and 0.3 or 0.12),
			cellHover = shade(light and 0.5 or 0.22),
			stroke = shade(light and -0.3 or 0.3),
			buttonHover = shade(light and 0.4 or 0.17),
			text = text,
			subtext = text:Lerp(bg, 0.4),
			accent = accent,
			accentHover = accent:Lerp(white, 0.2),
		} }
	end
end

-- Themes the user made: { id, name, bg, accent, text } with colors stored as hex.
local customThemes = {}
do
	local saved = plugin:GetSetting(SETTING.customThemes)
	if type(saved) == "table" then
		for _, record in saved do
			if type(record) == "table" and record.id and record.name and record.bg and record.accent and record.text then
				table.insert(customThemes, record)
			end
		end
	else
		-- Carry over the single custom theme from the previous version.
		local old = plugin:GetSetting(SETTING.customTheme)
		if type(old) == "table" and old.bg and old.accent and old.text then
			table.insert(customThemes, { id = HttpService:GenerateGUID(false), name = "My Theme", bg = old.bg, accent = old.accent, text = old.text })
		end
	end
end

local function customTheme(record)
	local ok, theme = pcall(function()
		return deriveTheme(Color3.fromHex(record.bg), Color3.fromHex(record.accent), Color3.fromHex(record.text))
	end)
	if not ok then
		return nil
	end
	theme.name, theme.id, theme.record = record.name, record.id, record
	return theme
end

local function themeKey(theme)
	return theme.id and ("custom:" .. theme.id) or theme.name
end

local COLORS = {}
local currentTheme = THEMES[1]

local function themeList()
	local list = table.clone(THEMES)
	for _, record in customThemes do
		local theme = customTheme(record)
		if theme then
			table.insert(list, theme)
		end
	end
	return list
end

local function loadThemeColors(theme)
	currentTheme = theme
	for k, v in theme.colors do
		COLORS[k] = v
	end
	for k, v in FIXED_COLORS do
		COLORS[k] = v
	end
	COLORS.titlebar = COLORS.header
	COLORS.onAccent = luminance(COLORS.accent) > 0.65 and Color3.fromRGB(30, 30, 30) or Color3.new(1, 1, 1)
end

do
	local saved = plugin:GetSetting(SETTING.theme)
	local theme = THEMES[1]
	for _, t in themeList() do
		-- "Custom" was the single custom theme's key in the previous version.
		if themeKey(t) == saved or (saved == "Custom" and t.record) then
			theme = t
		end
	end
	loadThemeColors(theme)
end

local uiTransparency = math.clamp(tonumber(plugin:GetSetting(SETTING.transparency)) or 0, 0, MAX_TRANSPARENCY)
local spawnWithLabel = plugin:GetSetting(SETTING.spawnWithLabel) ~= false

local FONT = Enum.Font.BuilderSansMedium
local FONT_BOLD = Enum.Font.BuilderSansBold

---------------------------------------------------------------------------
-- Marketplace filters (mirrors roblox.com/catalog)
---------------------------------------------------------------------------

local CATEGORIES
do
	local AT = Enum.AvatarAssetType
	local BT = Enum.BundleType

	local function category(label, assets, bundles, extra)
		local c = { label = label, assets = assets or {}, bundles = bundles or {} }
		for k, v in extra or {} do
			c[k] = v
		end
		return c
	end

	local function sub(label, assets, bundles, extra)
		local c = category(label, assets, bundles, extra)
		c.indent = true
		return c
	end

	local LAYERED_CLOTHING = {
		AT.TShirtAccessory, AT.ShirtAccessory, AT.PantsAccessory, AT.JacketAccessory, AT.SweaterAccessory,
		AT.ShortsAccessory, AT.DressSkirtAccessory,
	}

	CATEGORIES = {
		category("All"),

		category("Body", { AT.HairAccessory }, { BT.BodyParts, BT.DynamicHead, BT.DynamicHeadAvatar }),
		sub("Full Bodies", {}, { BT.BodyParts, BT.DynamicHeadAvatar }),
		sub("Hair", { AT.HairAccessory }),
		sub("Heads", {}, { BT.DynamicHead }),

		category("Clothing", {
			AT.TShirtAccessory, AT.ShirtAccessory, AT.PantsAccessory, AT.JacketAccessory, AT.SweaterAccessory,
			AT.ShortsAccessory, AT.DressSkirtAccessory, AT.LeftShoeAccessory, AT.RightShoeAccessory,
			AT.Shirt, AT.TShirt, AT.Pants,
		}, { BT.Shoes }),
		sub("Shirts", { AT.ShirtAccessory }),
		sub("T-Shirts", { AT.TShirtAccessory }),
		sub("Sweaters", { AT.SweaterAccessory }),
		sub("Jackets", { AT.JacketAccessory }),
		sub("Pants", { AT.PantsAccessory }),
		sub("Dresses & Skirts", { AT.DressSkirtAccessory }),
		-- Studio's catalog API has no bodysuit type, so this searches layered clothing for "bodysuit".
		sub("Bodysuits", LAYERED_CLOTHING, {}, { keyword = "bodysuit" }),
		sub("Shorts", { AT.ShortsAccessory }),
		sub("Shoes", { AT.LeftShoeAccessory, AT.RightShoeAccessory }, { BT.Shoes }),
		sub("Classic Shirts", { AT.Shirt }),
		sub("Classic T-Shirts", { AT.TShirt }),
		sub("Classic Pants", { AT.Pants }),

		category("Accessories", {
			AT.Hat, AT.FaceAccessory, AT.NeckAccessory, AT.ShoulderAccessory, AT.FrontAccessory,
			AT.BackAccessory, AT.WaistAccessory, AT.Gear,
		}),
		sub("Head", { AT.Hat }),
		sub("Face", { AT.FaceAccessory }),
		sub("Neck", { AT.NeckAccessory }),
		sub("Shoulder", { AT.ShoulderAccessory }),
		sub("Front", { AT.FrontAccessory }),
		sub("Back", { AT.BackAccessory }),
		sub("Waist", { AT.WaistAccessory }),
		sub("Gear", { AT.Gear }),

		category("Backgrounds", { AT.AvatarBackground }),

		category("Animations", { AT.EmoteAnimation }, { BT.Animations }),
		sub("Bundles", {}, { BT.Animations }),
		sub("Emotes", { AT.EmoteAnimation }),

		category("Makeup", { AT.EyeMakeup, AT.LipMakeup, AT.FaceMakeup, AT.EyelashAccessory, AT.EyebrowAccessory }),
		sub("Eyes", { AT.EyeMakeup }),
		sub("Lips", { AT.LipMakeup }),
		sub("Face", { AT.FaceMakeup }),
		sub("Eyelashes", { AT.EyelashAccessory }),
		sub("Eyebrows", { AT.EyebrowAccessory }),
	}
end

local SORTS = {
	{ "Relevance", Enum.CatalogSortType.Relevance, false },
	{ "Most Favorited", Enum.CatalogSortType.MostFavorited, true },
	{ "Bestselling", Enum.CatalogSortType.Bestselling, true },
	{ "Recently Published", Enum.CatalogSortType.RecentlyCreated, false },
	{ "Price (High to Low)", Enum.CatalogSortType.PriceHighToLow, false },
	{ "Price (Low to High)", Enum.CatalogSortType.PriceLowToHigh, false },
}

local PERIODS = {
	{ "All Time", Enum.CatalogSortAggregation.AllTime },
	{ "Past Week", Enum.CatalogSortAggregation.PastWeek },
	{ "Past Day", Enum.CatalogSortAggregation.PastDay },
}

local SALES_TYPES = {
	{ "All", Enum.SalesTypeFilter.All },
	{ "Limited", Enum.SalesTypeFilter.Collectibles },
	{ "Timed Options", Enum.SalesTypeFilter.TimedOptions },
}

local filters = {
	category = 1,
	creator = "",
	minPrice = nil,
	maxPrice = nil,
	sort = 1,
	period = 1,
	sales = 1,
	showUnavailable = false,
}

---------------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------------

-- Colors given as "@role" are bound to the theme and recolored when it changes. This is a strong
-- table cleared on Destroying: Instances aren't reliable weak-table keys in Roblox, and entries
-- vanishing early left parts of the UI stuck on an old theme's colors.
local themed = {}
-- Backgrounds that fade with the UI transparency slider; buttons and the title bar stay solid.
local SURFACE_ROLES = { panel = true, header = true, input = true, popup = true, cell = true, cellHover = true, buttonHover = true }
local TEXT_ROLES = { text = true, subtext = true }

local function applyRole(inst, prop, role)
	inst[prop] = COLORS[role]
	if prop == "BackgroundColor3" then
		inst.BackgroundTransparency = SURFACE_ROLES[role] and uiTransparency or 0
	elseif prop == "TextColor3" and TEXT_ROLES[role] then
		-- Light themes (Cherry Blossom) outline their white text so it stays readable.
		local outline = currentTheme.textStroke
		inst.TextStrokeColor3 = outline or Color3.new(0, 0, 0)
		inst.TextStrokeTransparency = outline and 0.45 or 1
	end
end

local function bindColor(inst, prop, role)
	local props = themed[inst]
	if not props then
		props = {}
		themed[inst] = props
		inst.Destroying:Connect(function()
			themed[inst] = nil
		end)
	end
	props[prop] = role
	applyRole(inst, prop, role)
end

local function setProps(inst, props)
	for k, v in props do
		if k ~= "Parent" then
			if type(v) == "string" and string.sub(v, 1, 1) == "@" and string.find(k, "Color") then
				bindColor(inst, k, string.sub(v, 2))
			else
				inst[k] = v
			end
		end
	end
end

local function create(className, props, children)
	local inst = Instance.new(className)
	setProps(inst, props)
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function round()
	return create("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke(role, thickness)
	return create("UIStroke", {
		Color = "@" .. (role or "stroke"),
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(px)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	})
end

local function hpadding(left, right)
	return create("UIPadding", { PaddingLeft = UDim.new(0, left), PaddingRight = UDim.new(0, right or left) })
end

local function hover(button, normalRole, hoverRole)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = COLORS[hoverRole]
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = COLORS[normalRole]
	end)
end

local function isOver(gui, pos)
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Studio follows every right click with a fake left click on the same spot (about 1 ms after the
-- right button comes up), so a left press arriving that soon after a right release is ignored.
local RIGHT_CLICK_ECHO = 0.15 -- seconds
local lastRightRelease = -math.huge
local rightReleaseConnection = UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		lastRightRelease = os.clock()
	end
end)

-- Runs `fn` when the left button is really pressed and released on `button`. Every button in the
-- plugin uses this instead of MouseButton1Click, which also fires for Studio's fake left click.
local function onLeftClick(button, fn)
	local pressed = false
	button.InputBegan:Connect(function(input)
		if isPress(input) then
			pressed = os.clock() - lastRightRelease > RIGHT_CLICK_ECHO
		elseif input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3 then
			pressed = false
		end
	end)
	button.InputEnded:Connect(function(input)
		if pressed and isPress(input) then
			pressed = false
			if isOver(button, input.Position) then
				fn()
			end
		end
	end)
end

local function trim(text)
	return (text:match("^%s*(.-)%s*$"))
end

-- Default position sits in a button's right padding, past the end of the text
-- (padding offsets child positions).
local function chevron(parent, position)
	local holder = create("Frame", {
		Size = UDim2.fromOffset(12, 8),
		Position = position or UDim2.new(1, 20, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	for _, side in { -1, 1 } do
		create("Frame", {
			Size = UDim2.fromOffset(8, 2),
			Position = UDim2.new(0.5, side * 2.5, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = side * -45,
			BackgroundColor3 = "@text",
			BorderSizePixel = 0,
			Parent = holder,
		})
	end
	return holder
end

local function gearIcon(parent)
	local holder = create("Frame", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	create("Frame", {
		Size = UDim2.fromOffset(11, 11),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = holder,
	}, { corner(6), stroke("text", 2.5) })
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		create("Frame", {
			Size = UDim2.fromOffset(4, 5),
			Position = UDim2.new(0.5, math.cos(angle) * 8, 0.5, math.sin(angle) * 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = i * 45 + 90,
			BackgroundColor3 = "@text",
			BorderSizePixel = 0,
			Parent = holder,
		})
	end
	return holder
end

-- A cherry blossom (🌸) over a soft white glow, which keeps it a light pink on any background.
local function blossom(parent, size, position)
	local holder = create("Frame", {
		Name = "Blossom",
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	create("Frame", {
		Size = UDim2.fromScale(0.8, 0.8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		Parent = holder,
	}, { round() })
	create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "🌸",
		TextScaled = true,
		TextTransparency = 0.3,
		Parent = holder,
	})
	return holder
end

local function textBox(props)
	local box = create("TextBox", {
		BackgroundColor3 = "@input",
		ClearTextOnFocus = false,
		Font = FONT,
		PlaceholderColor3 = "@subtext",
		Text = "",
		TextSize = 16,
		TextColor3 = "@text",
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
	}, { corner(6), stroke(), hpadding(10) })
	setProps(box, props)
	box.Parent = props.Parent
	return box
end

-- Primary (accent) buttons get a cherry blossom look while that theme is active.
local primaryButtons = {}

local function styleCherryButton(button, on)
	if on == (button:FindFirstChild("CherryIcon") ~= nil) then
		return
	end
	if on then
		create("UIGradient", {
			Name = "CherryGradient",
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 205, 222)),
			Rotation = 90,
			Parent = button,
		})
		create("UIStroke", {
			Name = "CherryStroke",
			Color = Color3.new(1, 1, 1),
			Transparency = 0.35,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = button,
		})
		blossom(button, 14, UDim2.new(1, -10, 0, 10)).Name = "CherryIcon"
	else
		for _, name in { "CherryGradient", "CherryStroke", "CherryIcon" } do
			local part = button:FindFirstChild(name)
			if part then
				part:Destroy()
			end
		end
	end
end

local function primaryButton(props)
	local button = create("TextButton", {
		BackgroundColor3 = "@accent",
		AutoButtonColor = false,
		Font = FONT_BOLD,
		TextSize = 16,
		TextColor3 = "@onAccent",
	}, { corner(6) })
	setProps(button, props)
	hover(button, "accent", "accentHover")
	primaryButtons[button] = true
	button.Destroying:Connect(function()
		primaryButtons[button] = nil
	end)
	styleCherryButton(button, currentTheme.cherry == true)
	button.Parent = props.Parent
	return button
end

local function secondaryButton(props)
	local button = create("TextButton", {
		BackgroundColor3 = "@cell",
		AutoButtonColor = false,
		Font = FONT,
		TextSize = 15,
		TextColor3 = "@text",
	}, { corner(6), stroke() })
	setProps(button, props)
	hover(button, "cell", "cellHover")
	button.Parent = props.Parent
	return button
end

---------------------------------------------------------------------------
-- Build UI
---------------------------------------------------------------------------

local old = CoreGui:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

local sideOpen = false
local minimized = false

local screenGui = create("ScreenGui", {
	Name = GUI_NAME,
	Enabled = false,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- Invisible full-screen catcher that keeps receiving mouse movement during drags.
local dragCatcher = create("Frame", {
	Name = "DragCatcher",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Active = true,
	ZIndex = 100,
	Parent = screenGui,
})

local main = create("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(DEFAULT_W, DEFAULT_H),
	Position = UDim2.fromOffset(200, 100),
	BackgroundColor3 = "@panel",
	Active = true,
	ClipsDescendants = true,
	ZIndex = 2,
	Parent = screenGui,
}, { corner(8), stroke() })

-- Title bar ---------------------------------------------------------------

local titleBar = create("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, TITLE_H),
	BackgroundColor3 = "@titlebar",
	Active = true,
	Parent = main,
}, { corner(8) })

-- Square off the bottom corners of the title bar.
create("Frame", {
	Size = UDim2.new(1, 0, 0, 8),
	Position = UDim2.new(0, 0, 1, -8),
	BackgroundColor3 = "@titlebar",
	BorderSizePixel = 0,
	Parent = titleBar,
})

local titleLabel = create("TextLabel", {
	Size = UDim2.new(1, -170, 1, 0),
	Position = UDim2.fromOffset(14, 0),
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	RichText = true,
	Text = 'Catalog Loader <stroke color="#FFFFFF" thickness="2"><font color="#FF6EC7">V2</font></stroke>',
	TextSize = 20,
	TextColor3 = "@text",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = titleBar,
})

create("TextLabel", {
	Name = "Version",
	Size = UDim2.fromOffset(180, 24),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "V" .. VERSION,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.6,
	Parent = titleBar,
})

local function titleButton(name, x)
	local button = create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(34, 28),
		Position = UDim2.new(1, x, 0.5, -14),
		BackgroundColor3 = "@titlebar",
		AutoButtonColor = false,
		Font = FONT_BOLD,
		Text = "",
		TextSize = 26,
		TextColor3 = "@text",
		Parent = titleBar,
	}, { corner(4) })
	return button
end

local closeButton = titleButton("Close", -40)
closeButton.Text = "×"
hover(closeButton, "titlebar", "closeHover")

local minimizeButton = titleButton("Minimize", -78)
hover(minimizeButton, "titlebar", "buttonHover")

local settingsButton = titleButton("Settings", -116)
hover(settingsButton, "titlebar", "buttonHover")
gearIcon(settingsButton)

local minimizeIcon = create("Frame", {
	Size = UDim2.fromOffset(14, 2),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = "@text",
	BorderSizePixel = 0,
	Parent = minimizeButton,
})

local restoreIcon = create("Frame", {
	Size = UDim2.fromOffset(12, 12),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = minimizeButton,
}, { stroke("text", 1.5) })

-- Content -----------------------------------------------------------------

local content = create("Frame", {
	Name = "Content",
	Size = UDim2.new(1, 0, 1, -TITLE_H),
	Position = UDim2.fromOffset(0, TITLE_H),
	BackgroundTransparency = 1,
	Parent = main,
}, { padding(12) })

local searchBox = textBox({
	Name = "Search",
	Size = UDim2.new(1, -110, 0, 36),
	PlaceholderText = "Search the Marketplace...",
	Parent = content,
})

local searchButton = primaryButton({
	Name = "SearchButton",
	Size = UDim2.fromOffset(100, 36),
	Position = UDim2.new(1, -100, 0, 0),
	Text = "Search",
	Parent = content,
})

local filterBar = create("Frame", {
	Name = "Filters",
	Size = UDim2.new(1, 0, 0, 0),
	Position = UDim2.fromOffset(0, 46),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = content,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = true,
	}),
})

local targetLabel = create("TextLabel", {
	Name = "Target",
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "",
	TextSize = 16,
	TextColor3 = "@subtext",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = content,
})

local grid = create("ScrollingFrame", {
	Name = "Grid",
	BackgroundColor3 = "@header",
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = "@stroke",
	ScrollingDirection = Enum.ScrollingDirection.Y,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Active = true,
	Parent = content,
}, {
	corner(6),
	padding(8),
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(132, 190),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local emptyLabel = create("TextLabel", {
	Name = "Empty",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "",
	TextSize = 17,
	TextColor3 = "@subtext",
	Visible = false,
	ZIndex = 2,
	Parent = content,
})

-- Plain white on every theme; centered over the ID bar by relayout.
local statusLabel = create("TextLabel", {
	Name = "Status",
	Size = UDim2.new(1, 0, 0, 22),
	Position = UDim2.new(0, 0, 1, -(44 + 8 + 22)),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "",
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = content,
})

local bottomBar = create("Frame", {
	Name = "BottomBar",
	Size = UDim2.new(1, 0, 0, 44),
	Position = UDim2.new(0, 0, 1, -44),
	BackgroundTransparency = 1,
	Parent = content,
})

local saveButton = primaryButton({
	Name = "Folders",
	Size = UDim2.fromOffset(90, 44),
	Text = "Folders",
	Parent = bottomBar,
})

local spawnButton = primaryButton({
	Name = "SpawnNPC",
	Size = UDim2.fromOffset(124, 44),
	Position = UDim2.fromOffset(98, 0),
	Text = "Spawn NPC",
	Parent = bottomBar,
})

-- Female / Male switch above Spawn NPC: an accent pill slides under the chosen side.
local genderSwitch = create("Frame", {
	Name = "GenderSwitch",
	Size = UDim2.fromOffset(124, 24),
	Position = UDim2.fromOffset(98, -30),
	BackgroundColor3 = "@cell",
	Parent = bottomBar,
}, { corner(6), stroke() })

create("Frame", {
	Name = "Highlight",
	Size = UDim2.new(0.5, -3, 1, -4),
	Position = UDim2.fromOffset(2, 2),
	BackgroundColor3 = "@accent",
	ZIndex = 1,
	Parent = genderSwitch,
}, { corner(5) })

local genderButtons = {}
for i, gender in { "Female", "Male" } do
	genderButtons[string.lower(gender)] = create("TextButton", {
		Name = gender,
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale((i - 1) * 0.5, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = FONT_BOLD,
		Text = gender,
		TextSize = 13,
		TextColor3 = "@subtext",
		ZIndex = 2,
		Parent = genderSwitch,
	})
end

-- ID entry, kept centered but clear of the left buttons (see relayout).
local idBar = create("Frame", {
	Name = "IdBar",
	Size = UDim2.fromOffset(420, 44),
	BackgroundTransparency = 1,
	Parent = bottomBar,
})

local idBox = textBox({
	Name = "IdBox",
	Size = UDim2.new(1, -RIGHT_BUTTONS_W, 1, 0),
	PlaceholderText = "Paste an item ID or Marketplace link",
	Parent = idBar,
})

local importButton = primaryButton({
	Name = "Import",
	Size = UDim2.new(0, 110, 1, 0),
	Position = UDim2.new(1, -208, 0, 0),
	Text = "Import",
	Parent = idBar,
})

local fixButton = primaryButton({
	Name = "FixNPC",
	Size = UDim2.new(0, 90, 1, 0),
	Position = UDim2.new(1, -90, 0, 0),
	Text = "Fix NPC",
	Parent = idBar,
})

-- Resize handles (right edge, bottom edge, bottom-right corner)
local function resizeHandle(name, size, position, axis)
	local handle = create("Frame", {
		Name = name,
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Active = true,
		ZIndex = 20,
		Parent = main,
	})
	handle:SetAttribute("AxisX", axis.X)
	handle:SetAttribute("AxisY", axis.Y)
	return handle
end

local resizeHandles = {
	resizeHandle("ResizeRight", UDim2.new(0, 6, 1, -TITLE_H - 18), UDim2.new(1, -6, 0, TITLE_H), Vector2.new(1, 0)),
	resizeHandle("ResizeBottom", UDim2.new(1, -18, 0, 6), UDim2.new(0, 0, 1, -6), Vector2.new(0, 1)),
	resizeHandle("ResizeCorner", UDim2.fromOffset(18, 18), UDim2.new(1, -18, 1, -18), Vector2.new(1, 1)),
}
-- Grip dots so the corner reads as resizable.
for _, offset in { { 12, 12 }, { 8, 12 }, { 12, 8 }, { 4, 12 }, { 8, 8 }, { 12, 4 } } do
	create("Frame", {
		Size = UDim2.fromOffset(2, 2),
		Position = UDim2.fromOffset(offset[1] - 2, offset[2] - 2),
		BackgroundColor3 = "@subtext",
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = resizeHandles[3],
	})
end

-- Saved NPCs side panel ----------------------------------------------------

local savePanel = create("Frame", {
	Name = "SavedNPCs",
	Size = UDim2.fromOffset(SIDE_W, DEFAULT_H),
	BackgroundColor3 = "@panel",
	Active = true,
	Visible = false,
	ZIndex = 1,
	Parent = screenGui,
}, { corner(8), stroke() })

local side = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = savePanel,
}, { padding(12) })

local sideTitle = create("TextLabel", {
	Size = UDim2.new(1, -30, 0, 24),
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	Text = "Saved NPCs",
	TextSize = 20,
	TextColor3 = "@text",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = side,
})

create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromOffset(0, 25),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "Available in every place you open in Studio.\nDrag to reorder, double-click for more options.",
	TextSize = 13,
	TextColor3 = "@subtext",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = side,
})

local saveNpcButton = primaryButton({
	Name = "SaveNPC",
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.fromOffset(0, 60),
	Text = "Save NPC",
	Parent = side,
})

local previewBg = create("Frame", {
	Name = "Preview",
	BackgroundColor3 = "@cellHover",
	Active = true,
	ClipsDescendants = true,
	Parent = side,
}, {
	corner(8),
	stroke(),
	create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(110, 110, 110)),
		Rotation = 90,
	}),
})

local previewViewport = create("ViewportFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Ambient = Color3.fromRGB(175, 175, 175),
	LightColor = Color3.new(1, 1, 1),
	LightDirection = Vector3.new(-0.4, -1, -0.7),
	Parent = previewBg,
})
local previewWorld = Instance.new("WorldModel")
previewWorld.Parent = previewViewport
local previewCamera = Instance.new("Camera")
previewCamera.FieldOfView = 30
previewCamera.Parent = previewViewport
previewViewport.CurrentCamera = previewCamera

local previewHint = create("TextLabel", {
	Size = UDim2.new(1, -20, 1, 0),
	Position = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "Select a saved NPC to preview it in 3D",
	TextSize = 15,
	TextColor3 = "@text",
	TextWrapped = true,
	Parent = previewBg,
})

local previewName = create("TextLabel", {
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.new(0, 8, 1, -28),
	BackgroundTransparency = 1,
	Font = FONT_BOLD,
	Text = "",
	TextSize = 17,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.6,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = previewBg,
})

local actionRow = create("Frame", {
	Name = "Actions",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Parent = side,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local spawnSavedButton = secondaryButton({
	Name = "Spawn",
	Size = UDim2.new(1 / 3, -4, 1, 0),
	Text = "Spawn",
	LayoutOrder = 1,
	Parent = actionRow,
})

local renameSavedButton = secondaryButton({
	Name = "Rename",
	Size = UDim2.new(1 / 3, -4, 1, 0),
	Text = "Rename",
	LayoutOrder = 2,
	Parent = actionRow,
})

local newFolderButton = secondaryButton({
	Name = "NewFolder",
	Size = UDim2.new(1 / 3, -4, 1, 0),
	Text = "+ New Folder",
	LayoutOrder = 3,
	Parent = actionRow,
})

local savedSearch = textBox({
	Name = "SavedSearch",
	Size = UDim2.new(1, 0, 0, 32),
	PlaceholderText = "Search NPCs and folders...",
	TextSize = 15,
	Parent = side,
})

local folderBar = create("Frame", {
	Name = "SavingTo",
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Parent = side,
})

local savingToLabel = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "",
	TextSize = 14,
	TextColor3 = "@subtext",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = folderBar,
})

local savedList = create("ScrollingFrame", {
	Name = "SavedList",
	BackgroundColor3 = "@header",
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = "@stroke",
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = side,
}, {
	corner(6),
	padding(6),
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }),
})

-- Cherry Blossom decorations ------------------------------------------------

do
	local PETAL_COLORS = { Color3.fromRGB(255, 244, 247), Color3.fromRGB(255, 214, 226), Color3.fromRGB(255, 176, 200) }
	local petals = {}
	local petalLayers = {}
	local gradients = {}

	local function addPetals(parent, count)
		local layer = create("Frame", {
			Name = "Petals",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 15,
			Visible = false,
			Parent = parent,
		})
		for _ = 1, count do
			local petal = create("Frame", {
				Size = UDim2.fromOffset(math.random(8, 12), math.random(5, 7)),
				BackgroundColor3 = PETAL_COLORS[math.random(#PETAL_COLORS)],
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Parent = layer,
			}, { round() })
			table.insert(petals, {
				gui = petal,
				x = math.random(),
				y = math.random() * 1.1 - 0.1,
				speed = 0.035 + math.random() * 0.045,
				phase = math.random() * math.pi * 2,
				spin = (math.random() - 0.5) * 140,
				rot = math.random(0, 360),
			})
		end
		table.insert(petalLayers, layer)
	end

	local function addGradient(parent)
		table.insert(gradients, create("UIGradient", {
			Name = "CherryGradient",
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 212, 226)),
			Rotation = 90,
			Enabled = false,
			Parent = parent,
		}))
	end

	addPetals(main, 16)
	addPetals(savePanel, 8)
	addGradient(main)
	addGradient(savePanel)

	-- A small blossom before each title and a cluster after the main one.
	local decor = {
		blossom(titleBar, 20, UDim2.fromOffset(22, TITLE_H / 2)),
		blossom(titleBar, 16, UDim2.fromOffset(222, 14)),
		blossom(titleBar, 12, UDim2.fromOffset(238, 27)),
		blossom(side, 20, UDim2.fromOffset(10, 12)),
	}

	function api.setCherryDecor(on)
		for _, layer in petalLayers do
			layer.Visible = on
		end
		for _, gradient in gradients do
			gradient.Enabled = on
		end
		for _, flower in decor do
			flower.Visible = on
		end
		titleLabel.Position = UDim2.fromOffset(on and 40 or 14, 0)
		sideTitle.Position = UDim2.fromOffset(on and 26 or 0, 0)
		for button in primaryButtons do
			styleCherryButton(button, on)
		end
	end

	function api.stepPetals(dt, elapsed)
		for _, p in petals do
			p.y += p.speed * dt
			if p.y > 1.05 then
				p.y = -0.05
				p.x = math.random()
			end
			p.rot += p.spin * dt
			p.gui.Position = UDim2.fromScale(p.x + math.sin(elapsed * 0.8 + p.phase) * 0.03, p.y)
			p.gui.Rotation = p.rot
		end
	end

	api.setCherryDecor(currentTheme.cherry == true)
end

screenGui.Parent = CoreGui

---------------------------------------------------------------------------
-- Pointer dragging (window, resize, sliders, color wheel, list reordering)
---------------------------------------------------------------------------

local activeDrag = nil -- { move = function(Vector2), finish = function() }

-- `catchMouse` shows the full-screen catcher straight away; list rows show it once a drag really starts.
local function beginDrag(input, move, finish, catchMouse)
	activeDrag = { move = move, finish = finish }
	dragCatcher.Visible = catchMouse == true
	move(Vector2.new(input.Position.X, input.Position.Y))
end

local function updateDrag(input)
	if activeDrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		activeDrag.move(Vector2.new(input.Position.X, input.Position.Y))
	end
end

local function endDrag(input)
	if not activeDrag or not isPress(input) then
		return
	end
	local drag = activeDrag
	activeDrag = nil
	dragCatcher.Visible = false
	if drag.finish then
		drag.finish()
	end
end

dragCatcher.InputChanged:Connect(updateDrag)
dragCatcher.InputEnded:Connect(endDrag)

---------------------------------------------------------------------------
-- Popups (dropdowns, settings, menus, color picker)
---------------------------------------------------------------------------

local popupBlocker = create("TextButton", {
	Name = "PopupBlocker",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 80,
	Parent = screenGui,
})

local popup = nil
local popupOnClose = nil

local function closePopup()
	local onClose = popupOnClose
	popupOnClose = nil
	if popup then
		popup:Destroy()
		popup = nil
	end
	popupBlocker.Visible = false
	if onClose then
		onClose()
	end
end
-- Presses on non-button parts of a popup (sliders, the color wheel) fall through to the blocker,
-- so only close when the press really started outside the popup.
local lastPressPos = nil
popupBlocker.InputBegan:Connect(function(input)
	if isPress(input) then
		lastPressPos = input.Position
	end
end)
onLeftClick(popupBlocker, function()
	if popup and lastPressPos and isOver(popup, lastPressPos) then
		return
	end
	closePopup()
end)

-- `anchor` is a GuiObject to open below, or a Vector2 screen position (row menus).
local function openPopup(anchor, title, build, options)
	closePopup()
	options = options or {}
	popupBlocker.Visible = true
	local width = options.width or 280
	popup = create("Frame", {
		Name = "Popup",
		Size = UDim2.fromOffset(width, 100),
		BackgroundColor3 = "@popup",
		Active = true,
		ZIndex = 90,
		Parent = screenGui,
	}, { corner(8), stroke() })

	create("TextLabel", {
		Size = UDim2.new(1, -24, 0, 36),
		Position = UDim2.fromOffset(14, 4),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = title,
		TextSize = 18,
		TextColor3 = "@text",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = popup,
	})

	local list = create("ScrollingFrame", {
		Size = UDim2.new(1, -8, 0, 0),
		Position = UDim2.fromOffset(4, 42),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = "@stroke",
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = popup,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		create("UIPadding", { PaddingBottom = UDim.new(0, 6) }),
	})

	build(list)

	-- Rows use fixed offset heights, so measure them directly instead of waiting on the layout.
	local contentH = 6
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			contentH += child.Size.Y.Offset + 2
		end
	end
	local screen = screenGui.AbsoluteSize
	local listH = math.min(contentH, math.max(120, screen.Y - 140), options.maxHeight or 440)
	local height = 42 + listH + 6
	list.Size = UDim2.new(1, -8, 0, listH)
	popup.Size = UDim2.fromOffset(width, height)

	local ax, ay, ah
	if typeof(anchor) == "Vector2" then
		ax, ay, ah = anchor.X, anchor.Y, 0
	else
		ax, ay, ah = anchor.AbsolutePosition.X, anchor.AbsolutePosition.Y, anchor.AbsoluteSize.Y
	end
	local x = math.clamp(ax, 8, math.max(8, screen.X - width - 8))
	local y = ay + ah + 6
	if y + height > screen.Y - 8 then
		y = math.max(8, ay - height - 6)
	end
	popup.Position = UDim2.fromOffset(x, y)
	popupOnClose = options.onClose
	return popup
end

local function themeSwatch(parent, theme, position)
	if theme.cherry then
		return blossom(parent, 24, position)
	end
	local chip = create("Frame", {
		Size = UDim2.fromOffset(22, 22),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = theme.colors.panel,
		Parent = parent,
	}, { round(), create("UIStroke", { Color = theme.colors.accent, Thickness = 2 }) })
	create("Frame", {
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = theme.colors.accent,
		Parent = chip,
	}, { round() })
	return chip
end

local function radioRow(parent, order, text, selected, indent, onClick, theme)
	local row = create("TextButton", {
		Size = UDim2.new(1, -6, 0, 34),
		BackgroundColor3 = "@popup",
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { corner(4) })
	hover(row, "popup", "buttonHover")
	local x = indent and 32 or 12
	if theme then
		themeSwatch(row, theme, UDim2.new(0, x + 11, 0.5, 0))
		x += 32
	end
	create("TextLabel", {
		Size = UDim2.new(1, -(x + 40), 1, 0),
		Position = UDim2.fromOffset(x, 0),
		BackgroundTransparency = 1,
		Font = selected and FONT_BOLD or FONT,
		Text = text,
		TextSize = 16,
		TextColor3 = "@text",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local radio = create("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = row,
	}, { round(), stroke(selected and "accent" or "subtext", 1.5) })
	if selected then
		create("Frame", {
			Size = UDim2.fromOffset(10, 10),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = "@accent",
			Parent = radio,
		}, { round() })
	end
	onLeftClick(row, onClick)
	return row
end

local function menuRow(parent, order, text, onClick, danger)
	local row = create("TextButton", {
		Size = UDim2.new(1, -6, 0, 34),
		BackgroundColor3 = "@popup",
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { corner(4) })
	hover(row, "popup", "buttonHover")
	local label = create("TextLabel", {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = text,
		TextSize = 16,
		TextColor3 = danger and "@bad" or "@text",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	onLeftClick(row, function()
		onClick(row, label)
	end)
	return row, label
end

local function popupLabel(parent, order, text)
	return create("TextLabel", {
		Size = UDim2.new(1, -6, 0, 26),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = text,
		TextSize = 14,
		TextColor3 = "@subtext",
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	}, { hpadding(12) })
end

local function popupTextBox(parent, order, placeholder, text)
	local holder = create("Frame", {
		Size = UDim2.new(1, -6, 0, 42),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, { hpadding(8) })
	return textBox({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 3),
		PlaceholderText = placeholder,
		Text = text or "",
		Parent = holder,
	})
end

local function popupApply(parent, order, onClick)
	local holder = create("Frame", {
		Size = UDim2.new(1, -6, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, { hpadding(8) })
	local button = primaryButton({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 6),
		Text = "Apply",
		Parent = holder,
	})
	onLeftClick(button, onClick)
end

local function popupButton(parent, order, text, onClick)
	local holder = create("Frame", {
		Size = UDim2.new(1, -6, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, { hpadding(8) })
	local button = secondaryButton({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 4),
		Text = text,
		Font = FONT_BOLD,
		Parent = holder,
	})
	onLeftClick(button, onClick)
	return button
end

local function sliderRow(parent, order, fraction, onChange, onDone)
	local row = create("Frame", {
		Size = UDim2.new(1, -6, 0, 34),
		BackgroundTransparency = 1,
		Active = true,
		LayoutOrder = order,
		Parent = parent,
	})
	local track = create("Frame", {
		Size = UDim2.new(1, -44, 0, 6),
		Position = UDim2.new(0, 22, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = "@stroke",
		Parent = row,
	}, { round() })
	local fill = create("Frame", {
		Size = UDim2.fromScale(fraction, 1),
		BackgroundColor3 = "@accent",
		Parent = track,
	}, { round() })
	local knob = create("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromScale(fraction, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { round(), stroke("accent", 2) })
	row.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		beginDrag(input, function(pos)
			local f = math.clamp((pos.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
			fill.Size = UDim2.fromScale(f, 1)
			knob.Position = UDim2.fromScale(f, 0.5)
			onChange(f)
		end, onDone, true)
	end)
	return row
end

local function toggleRow(parent, order, text, value, onToggle)
	local row = create("TextButton", {
		Size = UDim2.new(1, -6, 0, 38),
		BackgroundColor3 = "@popup",
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { corner(4) })
	hover(row, "popup", "buttonHover")
	create("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = text,
		TextSize = 16,
		TextColor3 = "@text",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local switch = create("Frame", {
		Size = UDim2.fromOffset(44, 24),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = row,
	}, { round() })
	local knob = create("Frame", {
		Size = UDim2.fromOffset(18, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = switch,
	}, { round() })
	local function render()
		bindColor(switch, "BackgroundColor3", value and "accent" or "stroke")
		knob.Position = UDim2.new(value and 1 or 0, value and -12 or 12, 0.5, 0)
	end
	render()
	onLeftClick(row, function()
		value = not value
		render()
		onToggle(value)
	end)
	return row
end

-- Color picker ----------------------------------------------------------------

do
	local WHEEL_SIZE = 180
	local wheelImage = nil

	local function getWheelImage()
		if wheelImage then
			return wheelImage
		end
		local ok, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(WHEEL_SIZE, WHEEL_SIZE) })
		end)
		if not ok or not img then
			return nil
		end
		local buf = buffer.create(WHEEL_SIZE * WHEEL_SIZE * 4)
		local radius = WHEEL_SIZE / 2
		for y = 0, WHEEL_SIZE - 1 do
			for x = 0, WHEEL_SIZE - 1 do
				local dx, dy = (x + 0.5 - radius) / radius, (y + 0.5 - radius) / radius
				local d = math.sqrt(dx * dx + dy * dy)
				if d <= 1 then
					local i = (y * WHEEL_SIZE + x) * 4
					local color = Color3.fromHSV((math.atan2(-dy, dx) / (2 * math.pi)) % 1, d, 1)
					buffer.writeu8(buf, i, math.floor(color.R * 255 + 0.5))
					buffer.writeu8(buf, i + 1, math.floor(color.G * 255 + 0.5))
					buffer.writeu8(buf, i + 2, math.floor(color.B * 255 + 0.5))
					buffer.writeu8(buf, i + 3, math.floor(math.clamp((1 - d) * radius, 0, 1) * 255))
				end
			end
		end
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(WHEEL_SIZE, WHEEL_SIZE), buf)
		wheelImage = img
		return img
	end

	function api.destroyColorWheel()
		if wheelImage then
			wheelImage:Destroy()
			wheelImage = nil
		end
	end

	-- options: anchor, title, name (optional: shows a name box), targets = { { key, label, color } },
	-- onChange(key, color), onCommit(name), onCancel()
	function api.openColorPicker(options)
		local targets = options.targets
		local current = 1
		local h, s, v = targets[1].color:ToHSV()
		local committed = false
		local marker, darken, valueGradient, valueKnob, swatch, hexBox, nameBox
		local targetButtons = {}

		local function refresh(skipHex)
			local color = Color3.fromHSV(h, s, v)
			local angle = h * math.pi * 2
			if marker then
				marker.Position = UDim2.fromScale(0.5 + math.cos(angle) * s * 0.5, 0.5 - math.sin(angle) * s * 0.5)
				darken.BackgroundTransparency = v
			end
			valueGradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(h, s, 1))
			valueKnob.Position = UDim2.fromScale(v, 0.5)
			swatch.BackgroundColor3 = color
			if not skipHex then
				hexBox.Text = "#" .. color:ToHex():upper()
			end
			for i, button in targetButtons do
				bindColor(button, "BackgroundColor3", i == current and "accent" or "cell")
				bindColor(button, "TextColor3", i == current and "onAccent" or "text")
			end
		end

		local function set(nh, ns, nv, skipHex)
			h, s, v = nh, ns, nv
			local color = Color3.fromHSV(h, s, v)
			targets[current].color = color
			options.onChange(targets[current].key, color)
			refresh(skipHex)
		end

		openPopup(options.anchor, options.title, function(list)
			local order = 0
			local function nextOrder()
				order += 1
				return order
			end

			if options.name then
				nameBox = popupTextBox(list, nextOrder(), "Theme name", options.name)
			end

			if #targets > 1 then
				local tabs = create("Frame", {
					Size = UDim2.new(1, -6, 0, 38),
					BackgroundTransparency = 1,
					LayoutOrder = nextOrder(),
					Parent = list,
				}, {
					hpadding(8),
					create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
				})
				for i, target in targets do
					local button = create("TextButton", {
						Size = UDim2.new(1 / #targets, -4, 0, 32),
						AutoButtonColor = false,
						Font = FONT_BOLD,
						Text = target.label,
						TextSize = 14,
						LayoutOrder = i,
						Parent = tabs,
					}, { corner(6) })
					onLeftClick(button, function()
						current = i
						h, s, v = targets[i].color:ToHSV()
						refresh()
					end)
					targetButtons[i] = button
				end
			end

			local wheelRow = create("Frame", {
				Size = UDim2.new(1, -6, 0, WHEEL_SIZE + 12),
				BackgroundTransparency = 1,
				LayoutOrder = nextOrder(),
				Parent = list,
			})
			local image = getWheelImage()
			if image then
				local wheel = create("ImageLabel", {
					Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE),
					Position = UDim2.new(0.5, 0, 0, 6),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundTransparency = 1,
					Active = true,
					Parent = wheelRow,
				})
				wheel.ImageContent = Content.fromObject(image)
				darken = create("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(0, 0, 0),
					Parent = wheel,
				}, { round() })
				marker = create("Frame", {
					Size = UDim2.fromOffset(14, 14),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					ZIndex = 3,
					Parent = wheel,
				}, { round(), create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2.5 }) })
				wheel.InputBegan:Connect(function(input)
					if not isPress(input) then
						return
					end
					beginDrag(input, function(pos)
						local center = wheel.AbsolutePosition + wheel.AbsoluteSize / 2
						local dx = (pos.X - center.X) / (wheel.AbsoluteSize.X / 2)
						local dy = (pos.Y - center.Y) / (wheel.AbsoluteSize.Y / 2)
						set((math.atan2(-dy, dx) / (2 * math.pi)) % 1, math.min(1, math.sqrt(dx * dx + dy * dy)), v)
					end, nil, true)
				end)
			else
				create("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Font = FONT,
					Text = "Color wheel unavailable here. Type a hex color below.",
					TextWrapped = true,
					TextSize = 14,
					TextColor3 = "@subtext",
					Parent = wheelRow,
				})
			end

			-- Brightness slider: black on the left, full color on the right.
			local valueRow = create("Frame", {
				Size = UDim2.new(1, -6, 0, 30),
				BackgroundTransparency = 1,
				Active = true,
				LayoutOrder = nextOrder(),
				Parent = list,
			})
			local track = create("Frame", {
				Size = UDim2.new(1, -44, 0, 12),
				Position = UDim2.new(0, 22, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = valueRow,
			}, { round(), stroke() })
			valueGradient = create("UIGradient", { Parent = track })
			valueKnob = create("Frame", {
				Size = UDim2.fromOffset(18, 18),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = track,
			}, { round(), create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }) })
			valueRow.InputBegan:Connect(function(input)
				if not isPress(input) then
					return
				end
				beginDrag(input, function(pos)
					set(h, s, math.clamp((pos.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1))
				end, nil, true)
			end)

			local hexRow = create("Frame", {
				Size = UDim2.new(1, -6, 0, 44),
				BackgroundTransparency = 1,
				LayoutOrder = nextOrder(),
				Parent = list,
			}, { hpadding(8) })
			swatch = create("Frame", {
				Size = UDim2.fromOffset(36, 36),
				Position = UDim2.fromOffset(0, 4),
				Parent = hexRow,
			}, { corner(6), stroke() })
			hexBox = textBox({
				Size = UDim2.new(1, -44, 0, 36),
				Position = UDim2.fromOffset(44, 4),
				PlaceholderText = "#RRGGBB",
				Parent = hexRow,
			})
			hexBox.FocusLost:Connect(function()
				local ok, color = pcall(Color3.fromHex, trim(hexBox.Text))
				if ok then
					local nh, ns, nv = color:ToHSV()
					set(nh, ns, nv)
				else
					refresh()
				end
			end)

			local buttons = create("Frame", {
				Size = UDim2.new(1, -6, 0, 46),
				BackgroundTransparency = 1,
				LayoutOrder = nextOrder(),
				Parent = list,
			}, {
				hpadding(8),
				create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
			})
			local cancel = secondaryButton({
				Size = UDim2.new(0.5, -4, 0, 36),
				Text = "Cancel",
				LayoutOrder = 1,
				Parent = buttons,
			})
			local apply = primaryButton({
				Size = UDim2.new(0.5, -4, 0, 36),
				Text = "Apply",
				LayoutOrder = 2,
				Parent = buttons,
			})
			onLeftClick(cancel, closePopup)
			onLeftClick(apply, function()
				committed = true
				local name = nameBox and trim(nameBox.Text) or nil
				closePopup()
				options.onCommit(name)
			end)
		end, {
			width = 300,
			maxHeight = 520,
			onClose = function()
				if not committed then
					options.onCancel()
				end
			end,
		})
		refresh()
	end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function relayout()
	local top = 46 + filterBar.AbsoluteSize.Y + 10
	targetLabel.Position = UDim2.fromOffset(0, top)
	local gridTop = top + 28
	grid.Position = UDim2.fromOffset(0, gridTop)
	grid.Size = UDim2.new(1, 0, 1, -(gridTop + BOTTOM_AREA))
	emptyLabel.Position = UDim2.fromOffset(0, gridTop + 40)

	-- The bottom row is one centered group with the ID box in the exact middle: Folders and
	-- Spawn NPC on its left, Import and Fix on its right, the status line centered above it.
	local width = bottomBar.AbsoluteSize.X
	local boxW = math.clamp(width - 2 * (LEFT_BUTTONS_W + 12), 200, 380)
	local boxX = (width - boxW) / 2
	idBar.Position = UDim2.fromOffset(boxX, 0)
	idBar.Size = UDim2.fromOffset(boxW + RIGHT_BUTTONS_W, 44)
	spawnButton.Position = UDim2.fromOffset(boxX - 12 - spawnButton.Size.X.Offset, 0)
	genderSwitch.Position = UDim2.fromOffset(spawnButton.Position.X.Offset, -30)
	saveButton.Position = UDim2.fromOffset(spawnButton.Position.X.Offset - 8 - saveButton.Size.X.Offset, 0)
	statusLabel.Position = UDim2.new(0, boxX, 1, -(44 + 8 + 22))
	statusLabel.Size = UDim2.fromOffset(boxW, 22)
end

filterBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

local function layoutSidePanel()
	local innerH = savePanel.AbsoluteSize.Y - 24
	local top = 110
	local fixed = top + 8 + 34 + 6 + 32 + 6 + 20 + 6
	local previewH = math.clamp(math.floor((innerH - fixed) * 0.5), 110, 300)
	local y = top
	previewBg.Position = UDim2.fromOffset(0, y)
	previewBg.Size = UDim2.new(1, 0, 0, previewH)
	y += previewH + 8
	actionRow.Position = UDim2.fromOffset(0, y)
	y += 34 + 6
	savedSearch.Position = UDim2.fromOffset(0, y)
	y += 32 + 6
	folderBar.Position = UDim2.fromOffset(0, y)
	y += 20 + 6
	savedList.Position = UDim2.fromOffset(0, y)
	savedList.Size = UDim2.new(1, 0, 1, -y)
end

local function syncSidePanel()
	local pos, size = main.AbsolutePosition, main.AbsoluteSize
	savePanel.Position = UDim2.fromOffset(pos.X - SIDE_W - SIDE_GAP, pos.Y)
	savePanel.Size = UDim2.fromOffset(SIDE_W, size.Y)
	savePanel.Visible = sideOpen and not minimized
	layoutSidePanel()
end

main:GetPropertyChangedSignal("AbsolutePosition"):Connect(syncSidePanel)
main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	relayout()
	syncSidePanel()
end)

---------------------------------------------------------------------------
-- Status / targets
---------------------------------------------------------------------------

local statusToken = 0

-- Status messages clear themselves after a few seconds.
local function setStatus(text)
	statusToken += 1
	local token = statusToken
	statusLabel.Text = text
	task.delay(4, function()
		if statusToken == token then
			statusLabel.Text = ""
		end
	end)
end

local function findRig(inst)
	local cur = inst
	while cur and cur ~= game do
		if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function getTargets()
	local rigs, seen = {}, {}
	for _, inst in Selection:Get() do
		local rig = findRig(inst)
		if rig and not seen[rig] then
			seen[rig] = true
			table.insert(rigs, rig)
		end
	end
	return rigs
end

local function updateTargetLabel()
	local rigs = getTargets()
	if #rigs == 0 then
		targetLabel.Text = "No NPC selected: items are placed in Workspace"
		bindColor(targetLabel, "TextColor3", "subtext")
	elseif #rigs == 1 then
		targetLabel.Text = "Target NPC: " .. rigs[1].Name
		bindColor(targetLabel, "TextColor3", "accent")
	else
		local names = {}
		for i = 1, math.min(4, #rigs) do
			table.insert(names, rigs[i].Name)
		end
		local more = #rigs > 4 and (", +" .. (#rigs - 4) .. " more") or ""
		targetLabel.Text = ("Target NPCs (%d): %s%s"):format(#rigs, table.concat(names, ", "), more)
		bindColor(targetLabel, "TextColor3", "accent")
	end
end

---------------------------------------------------------------------------
-- Putting items on NPCs
---------------------------------------------------------------------------

local placeInFront, placeRigInFront, withUndo, placeObjects
do
	local function findRigAttachment(rig, name)
		for _, d in rig:GetDescendants() do
			if d:IsA("Attachment") and d.Name == name and d.Parent:IsA("BasePart")
				and not d:FindFirstAncestorWhichIsA("Accoutrement") and not d:FindFirstAncestorWhichIsA("Tool") then
				return d
			end
		end
		return nil
	end

	local function attachAccessory(rig, accessory)
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		local handle = accessory:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then
			accessory.Parent = rig
			return false
		end
		handle.Anchored = false
		for _, child in handle:GetChildren() do
			if child.Name == "AccessoryWeld" then
				child:Destroy()
			end
		end

		-- Layered clothing needs the engine's own fitting.
		if handle:FindFirstChildOfClass("WrapLayer") and humanoid then
			local ok = pcall(humanoid.AddAccessory, humanoid, accessory)
			if not ok then
				accessory.Parent = rig
			end
			return ok
		end

		local accAttachment = handle:FindFirstChildOfClass("Attachment")
		local rigAttachment = accAttachment and findRigAttachment(rig, accAttachment.Name)
		local part1, c0, c1
		if rigAttachment then
			part1, c0, c1 = rigAttachment.Parent, accAttachment.CFrame, rigAttachment.CFrame
		else
			-- Legacy hats (or rigs missing the attachment): fall back to the head.
			local head = rig:FindFirstChild("Head")
			if not head or not head:IsA("BasePart") then
				accessory.Parent = rig
				return false
			end
			part1, c0, c1 = head, accessory.AttachmentPoint, CFrame.new(0, head.Size.Y / 2, 0)
		end

		handle.CFrame = part1.CFrame * c1 * c0:Inverse()
		accessory.Parent = rig
		create("Weld", {
			Name = "AccessoryWeld",
			Part0 = handle,
			Part1 = part1,
			C0 = c0,
			C1 = c1,
			Parent = handle,
		})
		return true
	end

	-- Humanoid:EquipTool doesn't weld in edit mode, so build the RightGrip ourselves.
	local function equipTool(rig, tool)
		local handle = tool:FindFirstChild("Handle")
		local gripAttachment = findRigAttachment(rig, "RightGripAttachment")
		tool.Parent = rig
		if not handle or not handle:IsA("BasePart") or not gripAttachment then
			return true
		end
		local hand = gripAttachment.Parent
		local existing = hand:FindFirstChild("RightGrip")
		if existing then
			existing:Destroy()
		end
		handle.Anchored = false
		handle.CFrame = hand.CFrame * gripAttachment.CFrame * tool.Grip:Inverse()
		create("Weld", {
			Name = "RightGrip",
			Part0 = hand,
			Part1 = handle,
			C0 = gripAttachment.CFrame,
			C1 = tool.Grip,
			Parent = hand,
		})
		return true
	end

	local function isWearable(obj)
		return obj:IsA("Accoutrement") or obj:IsA("Clothing") or obj:IsA("ShirtGraphic") or obj:IsA("Tool")
			or obj:IsA("Decal") or obj:IsA("Animation") or obj:IsA("Folder") and obj:GetAttribute("AnimationPack")
	end

	local function applyToRig(rig, obj)
		if obj:IsA("Accoutrement") then
			return attachAccessory(rig, obj)
		elseif obj:IsA("Clothing") or obj:IsA("ShirtGraphic") then
			-- Replace whatever shirt / pants / t-shirt the NPC already wears.
			for _, child in rig:GetChildren() do
				if child.ClassName == obj.ClassName then
					child:Destroy()
				end
			end
			obj.Parent = rig
			return true
		elseif obj:IsA("Tool") then
			return equipTool(rig, obj)
		elseif obj:IsA("Decal") then
			local head = rig:FindFirstChild("Head")
			obj.Parent = head or rig
			return head ~= nil
		else
			obj.Parent = rig
			return true
		end
	end

	function placeInFront(obj)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local cf = CFrame.new(camera.CFrame.Position + camera.CFrame.LookVector * 12)
		if obj:IsA("Model") then
			obj:PivotTo(cf)
		elseif obj:IsA("BasePart") then
			obj.Anchored = true
			obj.CFrame = cf
		elseif obj:IsA("Accoutrement") or obj:IsA("Tool") then
			local handle = obj:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.Anchored = true
				handle.CFrame = cf
			end
		end
	end

	-- Stands a rig on the ground about 10 studs in front of the camera, facing it, in Workspace.
	function placeRigInFront(rig)
		local camera = workspace.CurrentCamera
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		local pos = camera.CFrame.Position + flat * 10

		local boxCf, boxSize = rig:GetBoundingBox()
		local pivotAboveFeet = rig:GetPivot().Position.Y - (boxCf.Position.Y - boxSize.Y / 2)
		local hit = workspace:Raycast(pos + Vector3.new(0, 50, 0), Vector3.new(0, -1000, 0))
		if hit then
			pos = Vector3.new(pos.X, hit.Position.Y + pivotAboveFeet, pos.Z)
		end

		rig:PivotTo(CFrame.lookAt(pos, pos - flat))
		rig.Parent = workspace
	end

	function withUndo(name, fn)
		local recording = ChangeHistoryService:TryBeginRecording(name)
		fn()
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		else
			ChangeHistoryService:SetWaypoint(name)
		end
	end

	-- Puts loaded objects on the selected NPCs, or into Workspace when none are selected.
	function placeObjects(objects, label)
		local rigs = getTargets()
		local placed = {}
		local applied, attempted = 0, 0
		withUndo("Import " .. label, function()
			for _, obj in objects do
				if #rigs > 0 and isWearable(obj) then
					for i, rig in rigs do
						local copy = i == #rigs and obj or obj:Clone()
						attempted += 1
						if applyToRig(rig, copy) then
							applied += 1
						end
					end
				else
					placeInFront(obj)
					obj.Parent = workspace
					table.insert(placed, obj)
				end
			end
		end)
		if #placed > 0 then
			Selection:Set(placed)
		end
		if attempted > 0 then
			-- What you just put on is part of the layout Fix should restore.
			for _, rig in rigs do
				api.rememberPose(rig, true)
			end
		end

		if #rigs > 0 and attempted > 0 then
			if applied == attempted then
				setStatus(("Added %s to %d NPC%s"):format(label, #rigs, #rigs == 1 and "" or "s"))
			else
				setStatus(("Added %s, but some NPCs had no matching attachment"):format(label))
			end
		elseif #placed > 0 then
			local needsNpc = false
			for _, obj in placed do
				if obj:IsA("Clothing") or obj:IsA("ShirtGraphic") or obj:IsA("Decal") or obj:IsA("Animation") then
					needsNpc = true
				end
			end
			setStatus(needsNpc and ("Inserted %s into Workspace. Select an NPC to put it on."):format(label)
				or ("Inserted %s into Workspace"):format(label))
		end
	end
end

---------------------------------------------------------------------------
-- Loading assets and bundles
---------------------------------------------------------------------------

local function loadObjects(id)
	local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
	if ok and model then
		local objects = model:GetChildren()
		for _, obj in objects do
			obj.Parent = nil
		end
		model:Destroy()
		if #objects > 0 then
			return objects
		end
	end
	local ok2, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)
	end)
	if ok2 and #objects > 0 then
		return objects
	end
	return nil
end

local importBundle

local function importAsset(id, displayName, allowBundleFallback)
	local label = displayName or tostring(id)
	setStatus("Importing " .. label .. "...")
	task.spawn(function()
		local objects = loadObjects(id)
		if not objects then
			if allowBundleFallback then
				importBundle(id, displayName)
			else
				setStatus(("Couldn't import %s: it isn't available to insert."):format(label))
			end
			return
		end
		placeObjects(objects, displayName or objects[1].Name)
	end)
end

function importBundle(id, displayName)
	local label = displayName or ("bundle " .. id)
	setStatus("Importing " .. label .. "...")
	task.spawn(function()
		local ok, details = pcall(AssetService.GetBundleDetailsAsync, AssetService, id)
		if not ok then
			setStatus(("Couldn't import %s: not found."):format(label))
			return
		end
		label = details.Name or label
		local bundleType = tostring(details.BundleType)

		if bundleType == "Shoes" or bundleType:find("Animation") then
			local objects = {}
			for _, item in details.Items do
				if item.Type == "Asset" then
					for _, obj in loadObjects(item.Id) or {} do
						table.insert(objects, obj)
					end
				end
			end
			if bundleType:find("Animation") then
				local folder = create("Folder", { Name = label })
				folder:SetAttribute("AnimationPack", true)
				for _, obj in objects do
					obj.Parent = folder
				end
				objects = { folder }
			end
			if #objects == 0 then
				setStatus(("Couldn't import %s: it has no insertable items."):format(label))
				return
			end
			placeObjects(objects, label)
			return
		end

		-- Body / head bundles: build a full character from the bundle's outfit.
		local outfitId
		for _, item in details.Items do
			if item.Type == "UserOutfit" then
				outfitId = item.Id
			end
		end
		if not outfitId then
			setStatus(("Couldn't import %s: it has no outfit to build."):format(label))
			return
		end
		local ok2, character = pcall(function()
			local description = Players:GetHumanoidDescriptionFromOutfitId(outfitId)
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if not ok2 then
			setStatus(("Couldn't build %s: %s"):format(label, tostring(character)))
			return
		end
		character.Name = label
		withUndo("Import " .. label, function()
			placeInFront(character)
			character.Parent = workspace
		end)
		api.rememberPose(character, true)
		Selection:Set({ character })
		setStatus(("Spawned %s as a new R15 character"):format(label))
	end)
end

do
	local function parseInput(text)
		local bundleId = text:match("/bundles/(%d+)")
		if bundleId then
			return tonumber(bundleId), true
		end
		local id = text:match("/catalog/(%d+)")
			or text:match("/library/(%d+)")
			or text:match("[?&]id=(%d+)")
			or text:match("(%d+)")
		return id and tonumber(id), false
	end

	local function importFromBox()
		local id, isBundle = parseInput(idBox.Text)
		if not id then
			setStatus("Enter an item ID or Marketplace link.")
			return
		end
		if isBundle then
			importBundle(id)
		else
			importAsset(id, nil, true)
		end
	end

	onLeftClick(importButton, importFromBox)
	idBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			importFromBox()
		end
	end)
end

---------------------------------------------------------------------------
-- Spawn NPC
---------------------------------------------------------------------------

do
	local function inAccessory(part)
		return part ~= nil and part:FindFirstAncestorWhichIsA("Accoutrement") ~= nil
	end

	-- Re-aims accessory welds at where each accessory currently sits, so moved or resized
	-- accessories stay put (otherwise the old weld snaps them back when the game runs).
	function api.syncAccessoryWelds(model)
		for _, joint in model:GetDescendants() do
			if joint:IsA("JointInstance") and not joint:IsA("Motor6D") and joint.Part0 and joint.Part1
				and (inAccessory(joint.Part0) or inAccessory(joint.Part1)) then
				joint.C0 = joint.Part0.CFrame:Inverse() * joint.Part1.CFrame * joint.C1
			end
		end
	end

	-- Strips Studio's auto-join "Weld" joints (keeping any that hold accessories on) and,
	-- if turned off in Settings, the NPC Label.
	function api.prepareSpawn(rig)
		for _, d in rig:GetDescendants() do
			if d.Parent and d.Name == "Weld" and (d:IsA("JointInstance") or d:IsA("WeldConstraint"))
				and not inAccessory(d.Part0) and not inAccessory(d.Part1) then
				d:Destroy()
			end
		end
		api.syncAccessoryWelds(rig)
		if not spawnWithLabel then
			for _, d in rig:GetDescendants() do
				if d.Parent and d.Name == LABEL_NAME then
					d:Destroy()
				end
			end
		end
		return rig
	end

	-- The open place's own rig for this gender, if there is one.
	local function findPlaceTemplate(gender)
		local rigs = TEMPLATE_RIGS[gender]
		local cur = workspace
		for _, name in rigs.path do
			cur = cur and cur:FindFirstChild(name)
		end
		if cur and cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then
			return cur
		end
		for _, name in rigs.names do
			for _, d in workspace:GetDescendants() do
				if d.Name == name and d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then
					return d
				end
			end
		end
		return nil
	end

	-- Elaine's "Template" (Female) and "Template2" (Male) rigs, built into the plugin so Spawn NPC
	-- works in every place (SerializationService data, Zstd-compressed, Base64).
	local BUILT_IN_FEMALE = "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"
	local BUILT_IN_MALE = "KLUv/WACVx2/ANrG2ClWcJZVNQbHId6nLtiPLpT0YDFsvO1ic97ek8WbUvpToV6ygOObfOtQxWZfvtfW9nGqbXJbQr22sZERjIZhGFbpbEuAr49UlDxGp5ehKLff/+v/+99/yxRYAogCpwIbxTk+J9ICe5MMcxfLddf1ub1no1rlweXl+YD0ntZfXmB/sWFZBYdJs9rDcxcwFZunTuNoG3fLQ2EMFLaH/0c8PN1FqAL2+AzKbTjSYD/lBAQhw7e0/qDWWeEX6LmC/h6uo4AA+a0t36J6iPpYUzNzHfvwF3u9+3w+32+nxLh89xG5fQyZY+2Sz4Tchqzg+R8Aa0MTn0UX3TG1TMU2rM6stX+x3m7NhUtVp2krNrOq4iRCJguft7xbD/nE1aab/e5i5VXPwhgkFZuqEKnF4twNMrGKeVe2okQXi0v07hX9Mbn8hwlXjGYb1plZcd75zEU3vTl4ST5vVjFtxVtXlNW9YacCVErmz8brOqJYhDjl1VaPmQkNzUw2I61u2g8RTN06zbuyvWbZD9HLJIZFs9uXsnnVnh8il+mKHCkkJy66sr3Dtf9kK4ZMeKw7r5EbmtXdcsn0wK0Y6Ly5xCntP2sFjBFuNeNoqxZRNKlMMqbfePvTtyoGfajWjd4Zy09saqDUC+UCpPHfBsvMGr05nU8IvBiLiQDnrsoz1s5bYp3/phH40oLE3t601TuD/S+1gkP+46BZVX3qHJ6pcUSViweyrsdUry46z4zzX/WfxALC+C8jFEMxDEUxjBGeSsAct2/5RnEOV969U/9DU/D2vwep6n1zGT2lWvx38cIe1XmnWS1XrMNT9brisrx5qfH/Ro0W9JN1PdqG/vwfp5APWy+FMyH/WQzVaDSsU/d/cd1o1gjorbvZucxnutv5//pvYUCa/zRuajtAJ/K/5U/FpFbBDWZ2+izSapE+8bwoDNCGiH3SjJIBLSCBS4oTEbfPi31OGM248gLR8L668ybZOZ1490zXrJPy1nw64fbFOqiQ0cUqzg09ndKc7nQy2XB84ZO3aSOar7pXVOfgJdlms/VGvASGEZppI2yXeIIiIXy7uZ9xHMcWGHp249gbR9MMLCV67R0OGnd5VbzRn9vtqjrjOI6kE+/yrDVeykmNU5oZTVSn1dtY5n1zeuvGcez9761mqsaV6M34cQpsNRoh4pUoVm+6olet3X1No/LOWFSdCXfTadGEzzR3Vzx03pyqg9ILdN6NgUobzbUXcMYn4vYNxeqmkTSozjFaLxBOktc153akuCECL8ZcmEymkhMwFslL6cQzc+AwJRcQ/vNAcpteHA0lXsFRsmfROkwPxmFg3PZUFFyMGYEpjcEd0ZJKIZLbv0qkKwIosa4AgbkthcGYB1Gi9IYAAoieEnpVdU2U4hJleKZmKQEvxmDcsCyn3ohSokTpBQEEEL0kkECip6oxL/YRRXGHTfSngdjPBQ6fqdssq5QIIRTx+01oMuIlmRamOq32sF4pEen10jJj27DshSrROqrOSS4O45T4xLTa1nroIarkpjRUaOMVD+XM7KNrJ4qFE3F3gXCJYt1pQ39kuLwpzTxVfQQGho7/O87aeLXZhNaN4r3bIfnSlOi/uHMuy1SsRMvyi5QRmihe03zmkNQTTKllpFTXUKGVd5WcNySMqtoklV5wkrzLG5IFvlr4LMprNhL+RfgEBHZ2a2N2t+EpWMPsHOCgGbfy81JRfh82LDPgCPw8qO7D7nDPU+ccsTlcWr5jr/keceAe/A0YlReH5zAvIYEL8L+kfoP4GjwtfkPpDvC8iNZDQo7jDyHYyNabt7OqsxraQAEBsOEhlG15KP4kAztNExjr9jIsULGPqtMM7BVb4FGu0g3LgniQG5YFeRASJYXqlFNvZFQvnv6KttGb1WtEhTrCsRa2SVXMWPG5rhfIxEalloW3LZwaV118r9cTb07AG6qgjSdkzLBiY8WlqnnMrDt5VKqwhYrPW+aVh1t1OaoYYI4cqFChogIVKlRepUoVFKpUqRI8OjpK4ejoKGbIRrOOZP7Mgpxln7prwzoqWFD/F0CJNi+OttcbTxDhSp2u8VSsUwC9Odb+MqFlAruF0oQMTuQcRQZlLhP8/T+Z3+/38/l+TX6/PzlZeU4sVkQnFgMic3KbAexkCj282wwF4PBkBtARBHQ4qSN4BUlNATg8eeFWxuZnBIwKMRoYpCVfwhqkh+NdYpC5DR4yH3d4DXsShQle+LHCEs/RTPDCDx1OqpD+ASzxnAq/38aC8NsWpZcXC7AAURR/ouoUHCCn99Y4SFyMBdm6FP1RsQQJsKk6msoUlImBQ/O77Yk3uavemVF5VSUrNRab6M3R2VSNKlawiIqFhYWFhYWF5T8mUP7f749lEJIxUqnUC9x6fXL5pKVUvcvLM0S9uazOUuotA22dJM9WE+OgH3jfM83h2g3NuZtCR9AASpUU7okUKHJoYPM7C4/WFR2C/Ph35EBQgo3PBxdkCGKy+/H7ZThBigwbnw3Bp4gk8Drz3VjHJnTiJFiWSqVSZj6y3tC8N6apd98kN3glQuWykvDyoLohVadabaFMrYHwaf6gjIi91MqMS6/ac56Xx8RpmnUUxLC4cffVWfHWuR3cTrEOygWqc1EunzkoFAqFgWhinNKMznsEr0Sn0ajEQStWs44C3VmWQr+vTkG0MJ2I+LyhNzjVJ213gXYXKANx9sMPPzQJB+z0WaRVHkVQOkE7lgFrz3LLsjsH8tzgGHCAkA/JIeUsHTVWpN9rEFkv3VREwplgwFrYqSRa1hiG4QvXgyuTNdkTKWShpHx1Ik+2kFY9bkNRNJE6IOH2RG5DRC0I9vuJMNiSTIPBVjRmV8FSVmbARmAMFexXWsBMsFGKGvaz1Glajzkql3WIjMqMszJWLsZ0eGeawu5ShWV+qSjTDc2meWevHN6v1w6fPKzzblQvyar2seeZeV6v1+uFU94Cf9H6y+ZHw8V1suKEXCNRUcPFBEzLdTrA5dYnuk5zHA73O3HiZOWyQSGzs0ytTxzz1D2qKN5iojp3swsFvHG5XsAZm9nLdbSuMv3FW36ut9iUqFJzAP5Tkf+axP6yMT2BErsO8WH4HmIokjZIHCy0YPOj2fxobh++lOwUTPzftVxj0AAXi4obIQNhiHPoLZ83C6TpVY/sW6I6kgWEYU+6MkMHHS64QMRLsrWhqWYdcjyakd6Fwinv5ighZJCf8hUTJk1u//uNeIk9yvGTJAkDtBHiyjw0/iSSpSMaF/PgVCg1kxKRJwskg5hZcQ7vLpCJSRnAHirOtrxRbP7gyn2BSCBAampqanw+jGaZGP4kSXMiGaB6nWCHek+dDgeVOadzeKw4nzl3bTzWjWobDx5E7q5I3ajmKRJ0QpIkSZIlAXzkyVc6uhjzQVqS7PV65OmIBtljiA/bas1aJylmkPwFdkPzq+ViBY9Wa5RCprXDW8VGrPmDVR2LxWL9MZYRLkSW+cNisVirUQYJGHOxWq1Wq8u0bn2fIV5G6/bn+/1ioriGwNz6HVbJHcqp2kajIgUpCFUXfaGVVio4hHQS6SeRUl0LzqRatPJD9YQANGr03J7F27nUZ4YFqFN3bJyECqGZGZEkSdIBcxNgIBhsGJQLZ+NoHxPATSShoSwQCUSRCKJQBhkMIaOMmZkRGUn1sMSFv7FfhFpd/oGGLpCFfhq6UpVE56tMiI9VIDsj6qIA7cFr43PEXMRmlB9xgX0iZRa57esEiBeeWZ+hcMGBpfpQFBEdA1L5NdWlF+pMeuoEKeX4ku9RphRpRLqzl/kCQbILtpG632Q2QgphoBA2UVfts12ziO4AIBB4C9xB+j5KHISMvCtcTQMLKpHBwXVEaJ2SDeiiHEkzQ4rhvyJM3I698BZZ0Zysk7834lZiRkrWTwu/5msYy41Y2spp7qw1donIbL1BEuJV1F8nhW2JovhUKpqnhR5rlXAl6E6LSzVqQwqGskeYXVxVLVpEBeSUWN4AiejWzwkCOD72XiVRE616gheXtlWCfM67HtHXDdoVfNYuPMRnbl78+jt0QwcKclLlfNN0ILmot4gSmjw1QkC3vqlFp7L3mwSgfi6h/a8jxeYVRrvzYWaF+Zuxtmv4hiK1vuhaAaojKRf+AQUx26HmK+JEUMkxlYE1JNUdc0m6f8uPHnHBOZLYebAg3v0bWSNbF0UDErvcQUFXl910LLjur2b9NJoSciYaCkB+ZbaGgKRTP36woEbMs5x4oBDpQloGXVFmoh2xOaCToD7m5BtINl7wzaugC4XfNN2tmX12sP41g3PDZu+p9pCet9zDwXuqCioxOPTNCeIz2dOf7bpjd2CJH1GfJ1DP2AzTCKLqpd4SQlpMTRixqjeX5IeEz8ao6o2pkJy+VTKXo+hFdq+qb099Jx1JPhgR81pziuIx5m2WHPWmTLX4Li40NxUejX4ekZqaFr4jzNSY4or2aCGmCrBbI16qTA1BjO1Sx3xaPMwNsveDkcaJdpVCZQ+cn5atbsadjXqQQf4oL89F3XmIdXy0rJwu1QpokmBRV3WoUWUbE4A+URR6qBQBfGqOG65NNYI9ZUEHuXQaXUITRT2CD2sh4kc2TzaS4Rvzshi1VugAGFfXW/Dd4Necz4qMoclNGCJQ4v5gEwuorRi0zNEy1I/s3DuwBj9K8q5W9FBxK8oHRlR5kIakRaD116SDSFaIJI+uRGqn3n7xASA1rZtEXBAiuR3+PNQmPyKQ89K8iPwbau/tTGOMaJQnpUo3I0RUWpnaVFJhl4ozRFTZz78qlPcgMlj8DAmikZyxctIjKWibga3UxxYeOh9sXPo7JNEDey4BsCD6aXFxVobXECcD/5WREC4KhltPdCuC1ZaU6nzk9XVnEUUDkNzZ4wM2DwIZl92C0bJHIJPmNZIBixuPXZO5QjWPkKHKjMkiCsy01W0/k96S6V37Gt6cO8ehf4I04rt7iKpzBAdjTUa2dBWbnbNAGZbzROheZMb4hVYXhP65DL2XfGQ9lCcrHOF0sHCrkTz3E2Vzryc5pOv9imad9kb3ozzXcB3uXtjoJLwO4eTiSpQOH2Jc3qGtccEtyvE8E4hE/e39RNyrLo5T0FXbQjosftBCOF088QeuUKE2tEJtkT/nNd5hKdUQZ1IEN2qti37u6E+6A6qrUyELjvaq2ONSMfeCoeFikcMIehSbwIFRLLHEJ3H3halZZuqJeblpaGQd0AVJANQT0ttVHkapuqto0Xgb1pinnHbQ4csxFetx96gKCyXghZogvlCPflkFyF9bx8SfwVXPbMXJHS2peSnc+tmbz9eAz2NeSwSg3dQVQnb0YaUcbCk/xCY8saDgdaLZEA7nBGoJMKomIg5q0jqzq/DwNCH87+2fywvNfzgz7eDDcpTTbaddm7C6Oint7kphsKrODE2B6lPA+XQ/3lYZUCdFC42P28CaGc5qyFPKAAiUyUMRiyg8dCUZJsEDg5oFT5kIx1C94xwHry2uPo5eKmXgwDRY4Ly/be4a6JuiNgGkHdVhxMQdr7FKa/amdGm3kHpA++5YmwaYhOChE0uYnXfYvXMHSS72jjOU1qR8dy7pX5DcYTxQ6r8vwO0T67cEb9w4VAUjBkQRKj1C8pREYuYsBLcEgHxKlOoIWUkwfkhds9odPqW5XM1eKJExOr4tLHTGn+oYwcIqbz4tV5ltDhPnCpi3z4MGE2ZsmalHLZD0LNp4sGD14YMQlitD74J9681FJocu3cZEyQZA9AgwtEqxND212/mZ6IPofzu4ZwVBIJKfG84AoNst1bXdEvEYEiV0NfhIPQ89hS88ujXfWeuRLCtxMJgAZLf8qTT95piBJ5cBi8vVr4tTL755hhG+Wfv8dyAgpOR3X9yhhYdKXBq0oNLYRtz9Q+Idv5X82wGb9dVTMLZ1dJ7Zgfui2R2h8Eu/Ws3PPIjowWdmEXSttxdZKCx1CIls6pWl7A4r72X8OFH/uSxfW193sTXoZWzvMoLyGKHnjB2kUdaBZc3kBrrGbphAbima3/yhH4KvlspllE6UNCIlhD+gmzI9gpVuKV/KYuRojzDt0cP/qjBMXAdWpATceIw/0puEZ/HyaTqvDTGbwRuIbZX3UDaw7/k/ip1AKIODa5JcGM9UwZGL+5sUsuduQ5LCnyRJ3OfkUxuM4YpxC4h+J2DHEBtoLUo/l4RO8I5lANWyuD8WXLXOmZVx3BGhDQsUAyIXDkd439Ja7gDrh2wUeXKXYTWj+yZ/plqhvFC0ERHHSAKOQKjM6nhpYMqHhezKRAEEdmOrUc9M0xde6gHoUTUo+4AgZ9BgCPM0so/8bSymzANDwchRmHls3uKrNmAeN+mdCt78yI5qAoEwmqgy2eZq9qsL4Dia86H/MoCgiO4uQcEJTa2M8EhuaMVe+VwSP7qK3BUkqABbDP+sv5wElShOzZFkngdGV8FbER6FAdMZHkmiZ/ybUOlDtsd0gKH24MzocxAOl0nYKXqr8Luce6JgyvwdqcNbgJw7I3vm8y1lOMkvU4oIpFOLNAsTcEfdvR0AMalqGJG0zK++Q6dpOG/zmskagzFHw0r12ELk+SG2yfx3Ym88wQf12flbZpiwLbzhT+3i3G1BoPWXSzD7fZVO0DN/hhZAtjH8LDyvnxgMz0/D9kiNHOxPxYGNf7cuNGUwV5nYD/XAP6Zttdks1U6dpxDXKjXR7A3qy6zio9So8kjqqjXke5BQkjcrcS+L+899FbB4xtZBUEiA8vcbpfaEczqxJn4AOYNWUsCUo/c9DapcO9deI4Y2cWAU895T+lGOQRKVhz3B+oP7mYXfVn00b+3rtRvmNOz6a4lfUpSdqFH/PVKHJf4aHEBDmokRBJoN4Dc1+3YGOAVq6ODYXA/4gkluD83ckdscBRYnaZK4TQ6rqF4t6uVvH6KWUWBCYfE2DQUnLYdooK5WkUbyCZMvxWlnWw///gVKYUjOYkfHL34Y7+l4KZ424Xwyc6VnlfEAus3utia71rQVtQwhCXGeDp+etkq7khLIYzb85UoJQ7mMNCTpVO9MkMAQGrYjnZ+uaJkxVjMoqcRHkT+77gGv5t5BwsCLojovvfKR3IvV0St7s2yxPqRqp05K2SZzCkFi26+dDD/fRDOSlJaI5TBIT0pcbtvdcvUNmwAOuVlCboz5jsFzSlEitV9eXhZsDYzOG+SuM7OgiTH16dTjTprYE2dH8G0cMsqf7uMD6nas63CUNDDD9MzEVKVjSLdZSxMRXcK74mgXZnrVipN4N3rgZaVOCmbflTcQzg3J/VwlUujb7O6qvFmbZq4i/HLldmfTvHm4ACuUphUpifO4PXgnXdUDKUAVptDLmtbMn8KgfEmup8J/Vv91X094s0rgPWVsSIpaTNeyyxmOCN4491KA8Tk88rr40QUuC+I7r2IWy+afAD+UAzh74VHHh1+i2VnzXachgQDwrEfPo29J9ggTqNnHsMYG1+NiVOZAV8yzkXttMMh0BO2i8tCy/lIDN863zgWhyTf9sDPL+9UkOm0/3mfrxF1eAQBanucQO4UN/CECj4ys/BiXN4gjOog75nWludLHPrPrhRzYei5HWJPT/lqSQgYnsjgrpk0spiqMaOH595a8uJrCjYOG1xbWpCwg8TlEaBUk7IfYx5Q6UhC2w25oi+UWgVnJC/I3gomeLd2FznYUhnxoXQCRiKUKKo28ubdTAJD1bu+M/idRTLuh2sYDJCyvw30W6fSPvkUKD1zQtPYQB4bb00bK9k8stuxdAGv4pgUvdSaIzs32NiNaIiMCRJa3twxX3wB9R9zg9vmNTXaVjUQmrBzc/KVjgLpucIqop+d1rxqyIkVBqYknE+FqIwI+xlUNdMUoTPAQSWWqrLLCJVkUKwG4JKurQcjoRK3vN/tVnhlqc2f5qOX4O4Yy7dmlL0weJaEklxJPSa9EusZqVtdLSsFI8DTwNaQiJb7LcnvDZOOU1ux2fEkqji4JYP/Rt0i1pAoo0wo5+/LrCYK7/dzqzHYKQVSQ2NRFEIOQ2MLxtXg1qzGYCXYrMYGnGOMJxp6t7SsxeWqdIjlgqYUlgEVrtoTkFn2DcbVBbdfTx6hg1bHmsSyz7OsDZjRW5J3xVAHIVUhmWAAtSi6Vh87ihJN1hzBQXlG3QkCTsXfkuly/ow2LpE/4JgWzChoUvpsBUlWvIbr5ncPMcwk="
	local BUILT_IN_DATA = { female = BUILT_IN_FEMALE, male = BUILT_IN_MALE }
	local builtInTemplates = {} -- decoded copies, cached
	local gender = "female"

	-- The place's own rig for the chosen gender if it has one, else the built-in one.
	-- May yield while the built-in copy is decoded the first time.
	function api.findTemplate()
		local placeTemplate = findPlaceTemplate(gender)
		if placeTemplate then
			return placeTemplate
		end
		if not builtInTemplates[gender] then
			local ok, model = pcall(api.decodeModel, BUILT_IN_DATA[gender])
			if ok and model then
				builtInTemplates[gender] = model
			else
				warn("[Catalog Loader V2] Couldn't load the built-in " .. gender .. " template", model)
			end
		end
		return builtInTemplates[gender]
	end

	-- The pill's colors are fixed on every theme: pink for Female (its white text outlined like
	-- Cherry Blossom's), blue for Male. The unselected side's text follows the theme.
	local GENDER_STYLES = {
		female = { color = Color3.fromHex("#FFB6C1"), stroke = Color3.fromRGB(178, 62, 106) },
		male = { color = Color3.fromHex("#00A1FF") },
	}

	-- Takes a color off the theme so theme changes don't repaint it.
	local function unbindColor(inst, prop)
		if themed[inst] then
			themed[inst][prop] = nil
		end
	end

	local function showGender()
		local style = GENDER_STYLES[gender]
		local highlight = genderSwitch.Highlight
		highlight.Position = gender == "female" and UDim2.fromOffset(2, 2) or UDim2.new(0.5, 1, 0, 2)
		unbindColor(highlight, "BackgroundColor3")
		highlight.BackgroundColor3 = style.color
		for key, button in genderButtons do
			if key == gender then
				unbindColor(button, "TextColor3")
				button.TextColor3 = Color3.new(1, 1, 1)
				button.TextStrokeColor3 = style.stroke or Color3.new(0, 0, 0)
				button.TextStrokeTransparency = style.stroke and 0.45 or 1
			else
				setProps(button, { TextColor3 = "@subtext" })
			end
		end
	end
	showGender()
	for key, button in genderButtons do
		onLeftClick(button, function()
			gender = key
			showGender()
		end)
	end

	-- Clear the template copy the previous version kept in plugin settings.
	if plugin:GetSetting(SETTING.spawnTemplate) ~= nil then
		plugin:SetSetting(SETTING.spawnTemplate, nil)
		plugin:SetSetting(SETTING.spawnTemplateName, nil)
	end

	onLeftClick(spawnButton, function()
		local template = api.findTemplate()
		if not template or not workspace.CurrentCamera then
			setStatus("Couldn't load the NPC template.")
			return
		end
		local rig = api.prepareSpawn(template:Clone())
		withUndo("Spawn NPC", function()
			placeRigInFront(rig)
		end)
		api.rememberPose(rig, true)
		Selection:Set({ rig })
		setStatus("Spawned " .. rig.Name .. " in front of you")
	end)
end

---------------------------------------------------------------------------
-- Fix: put stray body parts (and the accessories on them) back in place
---------------------------------------------------------------------------

do
	-- Standard R6 joints, used to rebuild any that are missing (values match the Template rig).
	local R6_JOINTS = {
		{ name = "RootJoint", parent = "HumanoidRootPart", part0 = "HumanoidRootPart", part1 = "Torso",
			c0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), c1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
		{ name = "Neck", parent = "Torso", part0 = "Torso", part1 = "Head",
			c0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), c1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
		{ name = "Right Shoulder", parent = "Torso", part0 = "Torso", part1 = "Right Arm",
			c0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), c1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
		{ name = "Left Shoulder", parent = "Torso", part0 = "Torso", part1 = "Left Arm",
			c0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), c1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
		{ name = "Right Hip", parent = "Torso", part0 = "Torso", part1 = "Right Leg",
			c0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), c1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
		{ name = "Left Hip", parent = "Torso", part0 = "Torso", part1 = "Left Leg",
			c0 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), c1 = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	}
	-- An accessory within this many studs of its body part moved with it, so it keeps the offset you
	-- gave it; one further away was left behind and goes back to where its weld says it belongs.
	local NEAR = 12

	local function samePlace(a, b)
		return (a.Position - b.Position).Magnitude < 0.05 and a.LookVector:Dot(b.LookVector) > 0.9995
			and a.UpVector:Dot(b.UpVector) > 0.9995
	end

	local function findMotor(rig, part0, part1)
		for _, d in rig:GetDescendants() do
			if d:IsA("Motor6D") and (d.Part0 == part0 and d.Part1 == part1 or d.Part0 == part1 and d.Part1 == part0) then
				return d
			end
		end
		return nil
	end

	-- Where each R6 joint sits on its two parts, worked out from their sizes so rigs with bigger
	-- or smaller body parts fit too (for standard parts this gives the Template's values).
	local R6_OFFSETS = {
		RootJoint = function()
			return Vector3.zero, Vector3.zero
		end,
		Neck = function(s0, s1)
			return Vector3.new(0, s0.Y / 2, 0), Vector3.new(0, -s1.Y / 2, 0)
		end,
		["Right Shoulder"] = function(s0, s1)
			return Vector3.new(s0.X / 2, s0.Y / 4, 0), Vector3.new(-s1.X / 2, s1.Y / 4, 0)
		end,
		["Left Shoulder"] = function(s0, s1)
			return Vector3.new(-s0.X / 2, s0.Y / 4, 0), Vector3.new(s1.X / 2, s1.Y / 4, 0)
		end,
		["Right Hip"] = function(s0, s1)
			return Vector3.new(s0.X / 2, -s0.Y / 2, 0), Vector3.new(s1.X / 2, s1.Y / 2, 0)
		end,
		["Left Hip"] = function(s0, s1)
			return Vector3.new(-s0.X / 2, -s0.Y / 2, 0), Vector3.new(-s1.X / 2, s1.Y / 2, 0)
		end,
	}
	local R6_BY_PART = {}
	for _, joint in R6_JOINTS do
		R6_BY_PART[joint.part1] = joint
	end

	-- A joint's correct offsets: its matching RigAttachments (R15), otherwise the standard R6 joint
	-- sized to this rig. Nil when there's no reference, and that joint is left as it is.
	local function referenceOffsets(motor)
		for _, a0 in motor.Part0:GetChildren() do
			if a0:IsA("Attachment") and a0.Name:match("RigAttachment$") then
				local a1 = motor.Part1:FindFirstChild(a0.Name)
				if a1 and a1:IsA("Attachment") then
					return a0.CFrame, a1.CFrame
				end
			end
		end
		local joint = R6_BY_PART[motor.Part1.Name]
		if joint and motor.Part0.Name == joint.part0 then
			local at0, at1 = R6_OFFSETS[joint.name](motor.Part0.Size, motor.Part1.Size)
			return CFrame.new(at0) * joint.c0.Rotation, CFrame.new(at1) * joint.c1.Rotation
		end
		return nil
	end

	-- Where every body part belongs if `anchor` is where it should be, following the Motor6Ds.
	local function solveFrom(anchor, motors)
		local placed = { [anchor] = anchor.CFrame }
		local changed = true
		while changed do
			changed = false
			for _, motor in motors do
				local a, b = placed[motor.Part0], placed[motor.Part1]
				if a and not b then
					placed[motor.Part1] = a * motor.C0 * motor.C1:Inverse()
					changed = true
				elseif b and not a then
					placed[motor.Part0] = b * motor.C1 * motor.C0:Inverse()
					changed = true
				end
			end
		end
		return placed
	end

	-- The joint holding an accessory handle onto a body part, and that body part.
	local function accessoryJoint(rig, handle, body)
		for _, d in rig:GetDescendants() do
			if d:IsA("JointInstance") and not d:IsA("Motor6D") then
				if d.Part0 == handle and body[d.Part1] then
					return d, d.Part1
				elseif d.Part1 == handle and body[d.Part0] then
					return d, d.Part0
				end
			end
		end
		return nil
	end

	local function bodyAttachment(rig, name, body)
		for _, d in rig:GetDescendants() do
			if d:IsA("Attachment") and d.Name == name and body[d.Parent] then
				return d
			end
		end
		return nil
	end

	-- Pose memory ---------------------------------------------------------------
	-- The last known-good layout of each NPC: every part's offset from the root part, its size and
	-- its mesh scale. Kept in plugin settings (per place, by the NPC's path) rather than in the place,
	-- so remembering never touches the place or its undo history.

	local STRAY = 4 -- studs: an accessory further than this from its attachment spot is out of place
	local poses = plugin:GetSetting(SETTING.poses)
	if type(poses) ~= "table" then
		poses = {}
	end
	local savePending = false

	local function savePoses()
		if savePending then
			return
		end
		savePending = true
		task.delay(1, function()
			savePending = false
			plugin:SetSetting(SETTING.poses, poses)
		end)
	end

	-- Name of `inst` among its siblings, numbered when several share a name.
	local function siblingKey(inst)
		local n, index = 0, 0
		for _, sibling in inst.Parent:GetChildren() do
			if sibling.Name == inst.Name then
				n += 1
				if sibling == inst then
					index = n
				end
			end
		end
		return n > 1 and (inst.Name .. "#" .. index) or inst.Name
	end

	local function relPath(inst, ancestor)
		local names = {}
		local cur = inst
		while cur and cur ~= ancestor and cur.Parent do
			table.insert(names, 1, siblingKey(cur))
			cur = cur.Parent
		end
		return table.concat(names, "/")
	end

	local function rigKey(rig)
		return game.PlaceId .. ":" .. relPath(rig, game)
	end

	local function rootOf(rig)
		return rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart or rig:FindFirstChildWhichIsA("BasePart", true)
	end

	local function captureLayout(rig)
		local root = rootOf(rig)
		if not root then
			return nil
		end
		local layout = {}
		for _, part in rig:GetDescendants() do
			if part:IsA("BasePart") then
				local entry = {
					cf = { (root.CFrame:Inverse() * part.CFrame):GetComponents() },
					size = { part.Size.X, part.Size.Y, part.Size.Z },
				}
				local mesh = part:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					entry.scale = { mesh.Scale.X, mesh.Scale.Y, mesh.Scale.Z }
				end
				layout[relPath(part, rig)] = entry
			end
		end
		return layout
	end

	-- Whether an NPC looks put together: every body joint where its reference says, and no
	-- accessory far from its attachment spot. Only layouts like that are remembered automatically.
	local function isIntact(rig)
		local body = {}
		for _, motor in rig:GetDescendants() do
			if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 and motor.Part0.Parent and motor.Part1.Parent
				and not motor:FindFirstAncestorWhichIsA("Accoutrement") then
				body[motor.Part0], body[motor.Part1] = true, true
				local c0, c1 = referenceOffsets(motor)
				if not samePlace(motor.Part0.CFrame * (c0 or motor.C0), motor.Part1.CFrame * (c1 or motor.C1)) then
					return false
				end
			end
		end
		if next(body) == nil then
			return false
		end
		for _, acc in rig:GetDescendants() do
			local handle = acc:IsA("Accoutrement") and acc:FindFirstChild("Handle")
			local accAttachment = handle and handle:FindFirstChildOfClass("Attachment")
			local rigAttachment = accAttachment and bodyAttachment(rig, accAttachment.Name, body)
			if rigAttachment and (accAttachment.WorldPosition - rigAttachment.WorldPosition).Magnitude > STRAY then
				return false
			end
		end
		return true
	end

	-- Remembers the NPC's current layout; without `force`, only when it looks put together.
	local function rememberPose(rig, force)
		if not rig or not rig.Parent or not (force or isIntact(rig)) then
			return
		end
		local layout = captureLayout(rig)
		if layout then
			poses[rigKey(rig)] = { layout = layout, time = os.time() }
			savePoses()
		end
	end
	api.rememberPose = rememberPose

	-- Selected NPCs are remembered when selected and again when deselected, which catches the
	-- adjustments you make on purpose while leaving out ones that knocked something out of place.
	local watched = {}
	function api.rememberSelectedRigs()
		local current = {}
		for _, inst in Selection:Get() do
			local rig = findRig(inst)
			if rig then
				current[rig] = true
			end
		end
		for rig in watched do
			rememberPose(rig)
		end
		for rig in current do
			rememberPose(rig)
		end
		watched = current
	end

	-- First look at the place: remember every NPC we don't know yet that looks put together.
	function api.rememberAll()
		for _, humanoid in workspace:GetDescendants() do
			local rig = humanoid:IsA("Humanoid") and humanoid.Parent
			if rig and rig:IsA("Model") and not poses[rigKey(rig)] then
				rememberPose(rig)
			end
		end
	end

	-- What Fix restores an NPC to: its remembered pose, else your saved copy with the same name,
	-- else another NPC with the same name in Workspace that looks put together.
	-- Returns { layout, model?, source } or nil. May yield (loading a saved copy).
	local function findReference(rig)
		local memory = poses[rigKey(rig)]
		if memory and memory.layout then
			return { layout = memory.layout, source = "its remembered pose" }
		end
		local saved = api.findSavedModel and api.findSavedModel(rig.Name)
		if saved then
			return { layout = captureLayout(saved), model = saved, source = "your saved copy" }
		end
		for _, humanoid in workspace:GetDescendants() do
			local twin = humanoid:IsA("Humanoid") and humanoid.Parent
			if twin and twin ~= rig and twin:IsA("Model") and twin.Name == rig.Name and isIntact(twin) then
				return { layout = captureLayout(twin), model = twin, source = twin:GetFullName() }
			end
		end
		return nil
	end
	api.findReference = findReference

	-- Puts every part the layout knows back exactly: position, angle, size and mesh scale. The
	-- root goes wherever most parts agree it is, so one stray part never drags the rest along.
	-- Accessories the layout doesn't know (added since) keep their offset to their body part.
	local function applyLayout(rig, layout, body, report)
		local entries = {}
		for _, part in rig:GetDescendants() do
			if part:IsA("BasePart") then
				local entry = layout[relPath(part, rig)]
				if entry then
					entries[part] = {
						cf = CFrame.new(table.unpack(entry.cf)),
						size = Vector3.new(table.unpack(entry.size)),
						scale = entry.scale and Vector3.new(table.unpack(entry.scale)),
					}
				end
			end
		end

		local root, bestScore = nil, 0
		for part, entry in entries do
			local candidate = part.CFrame * entry.cf:Inverse()
			local score = 0
			for other, otherEntry in entries do
				if samePlace(other.CFrame, candidate * otherEntry.cf) then
					score += 1
				end
			end
			if score > bestScore or (score == bestScore and part.Name == "HumanoidRootPart") then
				root, bestScore = candidate, score
			end
		end
		if not root then
			return false
		end

		local followers = {}
		for _, acc in rig:GetDescendants() do
			local handle = acc:IsA("Accoutrement") and acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and not entries[handle] then
				local _, limb = accessoryJoint(rig, handle, body)
				local offset = limb and limb.CFrame:Inverse() * handle.CFrame
				if offset and offset.Position.Magnitude <= NEAR then
					followers[handle] = { limb = limb, offset = offset }
				end
			end
		end

		-- Anchor everything and switch joints off while moving, so each change moves only that part.
		local wasAnchored, disabled = {}, {}
		for _, part in rig:GetDescendants() do
			if part:IsA("BasePart") then
				wasAnchored[part] = part.Anchored
				part.Anchored = true
			elseif part:IsA("JointInstance") and part.Enabled then
				part.Enabled = false
				table.insert(disabled, part)
			end
		end

		for part, entry in entries do
			local changed = false
			if (part.Size - entry.size).Magnitude > 1e-3 then
				part.Size = entry.size
				changed = true
			end
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh and entry.scale and (mesh.Scale - entry.scale).Magnitude > 1e-3 then
				mesh.Scale = entry.scale
				changed = true
			end
			-- Always set the exact remembered CFrame; only noticeable moves count in the report.
			local target = root * entry.cf
			if not samePlace(part.CFrame, target) then
				changed = true
			end
			part.CFrame = target
			if changed then
				if part:FindFirstAncestorWhichIsA("Accoutrement") then
					report.accessories += 1
				else
					report.moved += 1
				end
			end
		end
		for handle, follower in followers do
			local target = follower.limb.CFrame * follower.offset
			if not samePlace(handle.CFrame, target) then
				handle.CFrame = target
				report.accessories += 1
			end
		end

		-- Every joint now describes the restored layout, so nothing snaps away when the game runs.
		for _, joint in disabled do
			if joint.Part0 and joint.Part1 then
				joint.C0 = joint.Part0.CFrame:Inverse() * joint.Part1.CFrame * joint.C1
			end
			joint.Enabled = true
		end
		for part, anchored in wasAnchored do
			part.Anchored = anchored
		end
		return true
	end

	-- Accessories with no joint at all get welded to their body part where they now sit.
	local function weldLooseAccessories(rig, body, report)
		for _, acc in rig:GetDescendants() do
			local handle = acc:IsA("Accoutrement") and acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") and not accessoryJoint(rig, handle, body) then
				local accAttachment = handle:FindFirstChildOfClass("Attachment")
				local rigAttachment = accAttachment and bodyAttachment(rig, accAttachment.Name, body)
				local limb = rigAttachment and rigAttachment.Parent or rig:FindFirstChild("Head")
				if limb and body[limb] then
					create("Weld", {
						Name = "AccessoryWeld",
						Part0 = handle,
						Part1 = limb,
						C1 = limb.CFrame:Inverse() * handle.CFrame,
						Parent = handle,
					})
					report.accessories += 1
				end
			end
		end
	end

	-- Parts or accessories that vanished come back from the reference copy. Their inner joints are
	-- dropped (body joints are rebuilt below) or pointed at this NPC's matching parts.
	local function restoreFromModel(rig, model, report)
		for _, child in model:GetChildren() do
			if (child:IsA("BasePart") or child:IsA("Accoutrement")) and not rig:FindFirstChild(child.Name) then
				local copy = child:Clone()
				for _, d in copy:GetDescendants() do
					if d:IsA("Motor6D") or (d:IsA("JointInstance") or d:IsA("WeldConstraint")) and copy:IsA("BasePart") then
						d:Destroy()
					elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
						for _, key in { "Part0", "Part1" } do
							local part = d[key]
							if part and not part:IsDescendantOf(copy) then
								d[key] = rig:FindFirstChild(part.Name)
							end
						end
					end
				end
				copy.Parent = rig
				report.restored += 1
			end
		end
	end

	-- Returns counts of what was repaired: { restored, joints, moved, accessories }.
	-- `reference` (from findReference) restores the exact layout; without one, body parts go back by
	-- their joints and accessories by their welds or attachments.
	function api.fixRig(rig, reference)
		local report = { restored = 0, joints = 0, moved = 0, accessories = 0 }

		if reference and reference.model then
			restoreFromModel(rig, reference.model, report)
		end

		-- Joints left pointing at a deleted part are useless; the ones below replace them.
		for _, d in rig:GetDescendants() do
			if d:IsA("Motor6D") and (not d.Part0 or not d.Part1 or not d.Part0.Parent or not d.Part1.Parent) then
				d:Destroy()
			end
		end

		-- Missing R6 limbs come back from the Template rig; missing joints get the standard values.
		if rig:FindFirstChild("Torso") then
			local template = api.findTemplate()
			for _, joint in R6_JOINTS do
				for _, name in { joint.part0, joint.part1 } do
					local source = template and template ~= rig and template:FindFirstChild(name)
					if not rig:FindFirstChild(name) and source then
						local part = source:Clone()
						for _, d in part:GetDescendants() do
							if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
								d:Destroy()
							end
						end
						part.Parent = rig
						report.restored += 1
					end
				end
			end
			for _, joint in R6_JOINTS do
				local part0, part1 = rig:FindFirstChild(joint.part0), rig:FindFirstChild(joint.part1)
				if part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") and not findMotor(rig, part0, part1) then
					create("Motor6D", {
						Name = joint.name,
						Part0 = part0,
						Part1 = part1,
						C0 = joint.c0,
						C1 = joint.c1,
						Parent = rig:FindFirstChild(joint.parent),
					})
					report.joints += 1
				end
			end
		end

		local motors, body = {}, {}
		for _, d in rig:GetDescendants() do
			if d:IsA("Motor6D") and d.Part0 and d.Part1 and d.Part0:IsDescendantOf(rig) and d.Part1:IsDescendantOf(rig)
				and not d:FindFirstAncestorWhichIsA("Accoutrement") then
				table.insert(motors, d)
				body[d.Part0], body[d.Part1] = true, true
			end
		end
		if #motors == 0 then
			return report
		end

		-- Dragging a body part in Studio rewrites its joint to match where it was dropped, so a
		-- scattered body still looks connected. Put every joint back to its reference offsets first.
		for _, motor in motors do
			local c0, c1 = referenceOffsets(motor)
			if c0 and not (samePlace(motor.C0, c0) and samePlace(motor.C1, c1)) then
				motor.C0, motor.C1 = c0, c1
				report.joints += 1
			end
		end

		-- Studio's auto-join welds between body parts would pin limbs in their wrong spots.
		for _, d in rig:GetDescendants() do
			if d.Parent and d.Name == "Weld" and d:IsA("JointInstance") and body[d.Part0] and body[d.Part1] then
				d:Destroy()
			end
		end

		if reference and applyLayout(rig, reference.layout, body, report) then
			weldLooseAccessories(rig, body, report)
			rememberPose(rig, true)
			return report
		end

		-- Anchor on the body part that agrees with the most others, so one stray part (even the
		-- torso) is pulled back instead of dragging the rest of the body after it.
		local best, bestScore = nil, -1
		for part in body do
			local score = 0
			for p, cf in solveFrom(part, motors) do
				if samePlace(p.CFrame, cf) then
					score += 1
				end
			end
			if score > bestScore or (score == bestScore and part.Name == "Torso") then
				best, bestScore = part, score
			end
		end
		local placed = solveFrom(best, motors)

		-- Work out where each accessory should end up before anything moves.
		local plans = {}
		for _, acc in rig:GetDescendants() do
			local handle = acc:IsA("Accoutrement") and acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				local joint, limb = accessoryJoint(rig, handle, body)
				local welded = joint
					and (joint.Part0 == handle and joint.C1 * joint.C0:Inverse() or joint.C0 * joint.C1:Inverse())
				-- The accessory's standard spot, from its attachment and the body part's matching one.
				local accAttachment = handle:FindFirstChildOfClass("Attachment")
				local rigAttachment = accAttachment and bodyAttachment(rig, accAttachment.Name, body)
				if not limb and rigAttachment then
					-- No joint at all: it gets reattached to the body part with the matching attachment.
					limb = rigAttachment.Parent
				end
				local standard = rigAttachment and rigAttachment.Parent == limb
					and rigAttachment.CFrame * accAttachment.CFrame:Inverse()
				if limb then
					local current = limb.CFrame:Inverse() * handle.CFrame
					local offset = current
					if current.Position.Magnitude > NEAR then
						-- Left behind or flung away: use the weld's offset if it still makes sense (Studio
						-- may have rewritten it when things were dragged), otherwise the standard spot.
						if welded and welded.Position.Magnitude <= NEAR then
							offset = welded
						elseif standard then
							offset = standard
						end
					end
					table.insert(plans, { handle = handle, joint = joint, limb = limb, offset = offset })
				end
			end
		end

		-- Anchor everything while moving so each CFrame change only moves that one part.
		local wasAnchored = {}
		local function hold(part)
			if wasAnchored[part] == nil then
				wasAnchored[part] = part.Anchored
				part.Anchored = true
			end
		end
		for part in body do
			hold(part)
		end
		for _, plan in plans do
			hold(plan.handle)
			if plan.joint then
				plan.joint.Enabled = false
			end
		end

		for part, cf in placed do
			if not samePlace(part.CFrame, cf) then
				part.CFrame = cf
				report.moved += 1
			end
		end
		for _, plan in plans do
			local target = plan.limb.CFrame * plan.offset
			if not samePlace(plan.handle.CFrame, target) then
				plan.handle.CFrame = target
				report.accessories += 1
			end
			if plan.joint then
				plan.joint.C0 = plan.joint.Part0.CFrame:Inverse() * plan.joint.Part1.CFrame * plan.joint.C1
				plan.joint.Enabled = true
			else
				create("Weld", {
					Name = "AccessoryWeld",
					Part0 = plan.handle,
					Part1 = plan.limb,
					C1 = plan.limb.CFrame:Inverse() * plan.handle.CFrame,
					Parent = plan.handle,
				})
				report.accessories += 1
			end
		end

		for part, anchored in wasAnchored do
			part.Anchored = anchored
		end
		rememberPose(rig, true)
		return report
	end

	local function count(n, word, plural)
		return ("%d %s"):format(n, n == 1 and word or plural or word .. "s")
	end

	onLeftClick(fixButton, function()
		local rigs = getTargets()
		if #rigs == 0 then
			setStatus("Select the NPC to fix in Studio, then click Fix.")
			return
		end
		setStatus("Fixing...")
		api.findTemplate() -- loads the built-in template now, since that can yield
		-- Find references first: loading a saved copy can yield, which mustn't happen mid-recording.
		local references, sources = {}, {}
		for _, rig in rigs do
			references[rig] = findReference(rig)
			if references[rig] then
				sources[references[rig].source] = true
			end
		end
		local total = { restored = 0, joints = 0, moved = 0, accessories = 0 }
		withUndo("Fix NPC", function()
			for _, rig in rigs do
				for key, n in api.fixRig(rig, references[rig]) do
					total[key] += n
				end
			end
		end)
		local changes = {}
		if total.restored > 0 then
			table.insert(changes, "restored " .. count(total.restored, "missing part"))
		end
		if total.joints > 0 then
			table.insert(changes, "rebuilt " .. count(total.joints, "joint"))
		end
		if total.moved > 0 then
			table.insert(changes, "moved " .. count(total.moved, "body part") .. " back")
		end
		if total.accessories > 0 then
			table.insert(changes, "reattached " .. count(total.accessories, "accessory", "accessories"))
		end
		local who = #rigs == 1 and rigs[1].Name or (#rigs .. " NPCs")
		local using = {}
		for source in sources do
			table.insert(using, source)
		end
		local from = #using > 0 and (" (from " .. table.concat(using, ", ") .. ")") or ""
		setStatus(#changes == 0 and (who .. " already looks fine")
			or ("Fixed " .. who .. ": " .. table.concat(changes, ", ") .. from))
	end)
end

---------------------------------------------------------------------------
-- Catalog results
---------------------------------------------------------------------------

local startSearch
do
	local searchGen = 0
	local currentPages = nil
	local loading = false
	local itemCount = 0

	local function clearGrid()
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		itemCount = 0
		grid.CanvasPosition = Vector2.zero
	end

	local function formatPrice(item)
		if item.Price == 0 then
			return "Free", "good"
		elseif item.Price then
			return "R$ " .. tostring(item.Price), "subtext"
		elseif item.LowestPrice and item.LowestPrice > 0 then
			return "R$ " .. tostring(item.LowestPrice), "subtext"
		end
		return "Off sale", "subtext"
	end

	local function addCell(item)
		itemCount += 1
		local isBundle = item.ItemType == "Bundle"
		local cell = create("ImageButton", {
			Name = tostring(item.Id),
			BackgroundColor3 = "@cell",
			AutoButtonColor = false,
			LayoutOrder = itemCount,
			Parent = grid,
		}, { corner(6) })
		hover(cell, "cell", "cellHover")

		local thumb = create("ImageLabel", {
			Size = UDim2.fromOffset(124, 124),
			Position = UDim2.fromOffset(4, 4),
			BackgroundColor3 = "@input",
			Image = ("rbxthumb://type=%s&id=%d&w=150&h=150"):format(isBundle and "BundleThumbnail" or "Asset", item.Id),
			Parent = cell,
		}, { corner(4) })

		if isBundle then
			create("TextLabel", {
				Size = UDim2.fromOffset(0, 18),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(4, 4),
				BackgroundColor3 = "@accent",
				Font = FONT_BOLD,
				Text = "Bundle",
				TextSize = 12,
				TextColor3 = "@onAccent",
				Parent = thumb,
			}, { corner(4), hpadding(6) })
		end

		create("TextLabel", {
			Size = UDim2.new(1, -10, 0, 18),
			Position = UDim2.fromOffset(5, 131),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = item.Name or "?",
			TextSize = 15,
			TextColor3 = "@text",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = cell,
		})

		create("TextLabel", {
			Size = UDim2.new(1, -10, 0, 16),
			Position = UDim2.fromOffset(5, 150),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = item.CreatorName and ("By " .. item.CreatorName) or "",
			TextSize = 13,
			TextColor3 = "@subtext",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = cell,
		})

		local priceText, priceRole = formatPrice(item)
		create("TextLabel", {
			Size = UDim2.new(1, -10, 0, 16),
			Position = UDim2.fromOffset(5, 168),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			Text = priceText,
			TextSize = 14,
			TextColor3 = "@" .. priceRole,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = cell,
		})

		onLeftClick(cell, function()
			if isBundle then
				idBox.Text = ("roblox.com/bundles/%d"):format(item.Id)
				importBundle(item.Id, item.Name)
			else
				idBox.Text = tostring(item.Id)
				importAsset(item.Id, item.Name)
			end
		end)
	end

	local function appendPage(page)
		for _, item in page do
			if item.Id then
				addCell(item)
			end
		end
		emptyLabel.Visible = itemCount == 0
		emptyLabel.Text = itemCount == 0 and "No items found." or ""
	end

	local function buildSearchParams()
		local cat = CATEGORIES[filters.category]
		local keyword = searchBox.Text
		if cat.keyword then
			keyword = cat.keyword .. " " .. keyword
		end
		local params = CatalogSearchParams.new()
		params.SearchKeyword = trim(keyword)
		params.AssetTypes = cat.assets
		params.BundleTypes = cat.bundles
		params.SortType = SORTS[filters.sort][2]
		if SORTS[filters.sort][3] then
			params.SortAggregation = PERIODS[filters.period][2]
		end
		params.SalesTypeFilter = SALES_TYPES[filters.sales][2]
		params.IncludeOffSale = filters.showUnavailable
		if filters.creator ~= "" then
			params.CreatorName = filters.creator
		end
		if filters.minPrice then
			params.MinPrice = filters.minPrice
		end
		if filters.maxPrice then
			params.MaxPrice = filters.maxPrice
		end
		params.Limit = PAGE_LIMIT
		return params
	end

	function startSearch()
		searchGen += 1
		local gen = searchGen
		clearGrid()
		currentPages = nil
		loading = true
		emptyLabel.Visible = true
		emptyLabel.Text = "Loading..."

		task.spawn(function()
			local ok, pages = pcall(AvatarEditorService.SearchCatalog, AvatarEditorService, buildSearchParams())
			if gen ~= searchGen then
				return
			end
			loading = false
			if not ok then
				emptyLabel.Visible = true
				emptyLabel.Text = "Couldn't load the Marketplace. Try again in a moment."
				warn("[Catalog Loader V2] SearchCatalog failed:", pages)
				return
			end
			currentPages = pages
			appendPage(pages:GetCurrentPage())
		end)
	end

	local function loadMore()
		if loading or not currentPages or currentPages.IsFinished then
			return
		end
		loading = true
		local gen = searchGen
		task.spawn(function()
			local ok, err = pcall(currentPages.AdvanceToNextPageAsync, currentPages)
			if gen ~= searchGen then
				return
			end
			loading = false
			if ok then
				appendPage(currentPages:GetCurrentPage())
			else
				warn("[Catalog Loader V2] Loading more failed:", err)
			end
		end)
	end

	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if grid.CanvasPosition.Y + grid.AbsoluteWindowSize.Y >= grid.AbsoluteCanvasSize.Y - 400 then
			loadMore()
		end
	end)

	onLeftClick(searchButton, startSearch)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			startSearch()
		end
	end)
end

---------------------------------------------------------------------------
-- Filter dropdowns
---------------------------------------------------------------------------

do
	local function filterButton(order, onClick)
		local button = create("TextButton", {
			Size = UDim2.fromOffset(0, 34),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = "@cell",
			AutoButtonColor = false,
			Font = FONT,
			Text = "",
			TextSize = 16,
			TextColor3 = "@text",
			LayoutOrder = order,
			Parent = filterBar,
		}, { corner(17), hpadding(14, 40) })
		chevron(button)
		button.MouseEnter:Connect(function()
			if not button:GetAttribute("Active") then
				button.BackgroundColor3 = COLORS.cellHover
			end
		end)
		button.MouseLeave:Connect(function()
			if not button:GetAttribute("Active") then
				button.BackgroundColor3 = COLORS.cell
			end
		end)
		onLeftClick(button, function()
			onClick(button)
		end)
		return button
	end

	local function applyFilters()
		closePopup()
		api.refreshFilterButtons()
		startSearch()
	end

	local categoryButton = filterButton(1, function(button)
		openPopup(button, "Category", function(list)
			for i, cat in CATEGORIES do
				radioRow(list, i, cat.label, filters.category == i, cat.indent, function()
					filters.category = i
					applyFilters()
				end)
			end
		end)
	end)

	local creatorButton = filterButton(2, function(button)
		openPopup(button, "Creator", function(list)
			radioRow(list, 1, "All Creators", filters.creator == "", false, function()
				filters.creator = ""
				applyFilters()
			end)
			radioRow(list, 2, "Roblox", filters.creator == "Roblox", false, function()
				filters.creator = "Roblox"
				applyFilters()
			end)
			local custom = filters.creator ~= "Roblox" and filters.creator or ""
			local box = popupTextBox(list, 3, "Creator Name", custom)
			popupApply(list, 4, function()
				filters.creator = trim(box.Text)
				applyFilters()
			end)
		end)
	end)

	local priceButton = filterButton(3, function(button)
		openPopup(button, "Price", function(list)
			radioRow(list, 1, "Any Price", filters.minPrice == nil and filters.maxPrice == nil, false, function()
				filters.minPrice, filters.maxPrice = nil, nil
				applyFilters()
			end)
			radioRow(list, 2, "Free", filters.minPrice == 0 and filters.maxPrice == 0, false, function()
				filters.minPrice, filters.maxPrice = 0, 0
				applyFilters()
			end)
			local minBox = popupTextBox(list, 3, "Min", filters.minPrice and tostring(filters.minPrice) or "")
			local maxBox = popupTextBox(list, 4, "Max", filters.maxPrice and tostring(filters.maxPrice) or "")
			popupApply(list, 5, function()
				filters.minPrice = tonumber(minBox.Text:match("%d+"))
				filters.maxPrice = tonumber(maxBox.Text:match("%d+"))
				if filters.minPrice and filters.maxPrice and filters.minPrice > filters.maxPrice then
					filters.minPrice, filters.maxPrice = filters.maxPrice, filters.minPrice
				end
				applyFilters()
			end)
		end)
	end)

	local sortButton = filterButton(4, function(button)
		openPopup(button, "Sort By", function(list)
			local order = 0
			for i, sort in SORTS do
				order += 1
				radioRow(list, order, sort[1], filters.sort == i, false, function()
					filters.sort = i
					filters.period = 1
					applyFilters()
				end)
				if sort[3] and filters.sort == i then
					for p, period in PERIODS do
						order += 1
						radioRow(list, order, period[1], filters.period == p, true, function()
							filters.period = p
							applyFilters()
						end)
					end
				end
			end
		end)
	end)

	local salesButton = filterButton(5, function(button)
		openPopup(button, "Sales Type", function(list)
			for i, sales in SALES_TYPES do
				radioRow(list, i, sales[1], filters.sales == i, false, function()
					filters.sales = i
					applyFilters()
				end)
			end
		end)
	end)

	local unavailableButton = filterButton(6, function(button)
		openPopup(button, "Unavailable Items", function(list)
			radioRow(list, 1, "Hide", not filters.showUnavailable, false, function()
				filters.showUnavailable = false
				applyFilters()
			end)
			radioRow(list, 2, "Show", filters.showUnavailable, false, function()
				filters.showUnavailable = true
				applyFilters()
			end)
		end)
	end)

	local function setFilterButton(button, text, active)
		button.Text = text
		button:SetAttribute("Active", active)
		bindColor(button, "BackgroundColor3", active and "accent" or "cell")
		bindColor(button, "TextColor3", active and "onAccent" or "text")
	end

	local function priceText()
		local lo, hi = filters.minPrice, filters.maxPrice
		if lo == nil and hi == nil then
			return "Any Price"
		elseif lo == 0 and hi == 0 then
			return "Free"
		elseif lo and hi then
			return ("R$ %d - %d"):format(lo, hi)
		elseif lo then
			return ("R$ %d+"):format(lo)
		end
		return ("Up to R$ %d"):format(hi)
	end

	function api.refreshFilterButtons()
		setFilterButton(categoryButton, CATEGORIES[filters.category].label, filters.category ~= 1)
		setFilterButton(creatorButton, filters.creator == "" and "All Creators" or filters.creator, filters.creator ~= "")
		setFilterButton(priceButton, priceText(), filters.minPrice ~= nil or filters.maxPrice ~= nil)
		local sort = SORTS[filters.sort]
		local sortText = "Sort by " .. sort[1]
		if sort[3] and filters.period ~= 1 then
			sortText ..= " (" .. PERIODS[filters.period][1] .. ")"
		end
		setFilterButton(sortButton, sortText, filters.sort ~= 1)
		setFilterButton(salesButton, filters.sales == 1 and "Sales Type" or SALES_TYPES[filters.sales][1], filters.sales ~= 1)
		setFilterButton(unavailableButton, filters.showUnavailable and "Showing Unavailable" or "Unavailable Items", filters.showUnavailable)
	end
	api.refreshFilterButtons()
end

---------------------------------------------------------------------------
-- Saved NPCs (stored in plugin settings, shared by every place)
---------------------------------------------------------------------------

do
	local savedIndex = plugin:GetSetting(SETTING.savedIndex)
	if type(savedIndex) ~= "table" then
		savedIndex = {}
	end
	savedIndex.folders = savedIndex.folders or {}
	savedIndex.npcs = savedIndex.npcs or {}
	api.savedIndex = savedIndex

	local modelCache = {}
	api.modelCache = modelCache
	local selectedId = nil
	local activeFolderId = nil
	local rowsById = {} -- id -> { row, label }
	local visualItems = {} -- rows in display order: { kind, ref, row }
	local folderBlockEnd = {} -- folder id -> last row shown for that folder
	local suppressClickUntil = 0
	local DOUBLE_CLICK = 0.4 -- seconds
	local lastClick = nil -- { id, time, collapsed } of the last row click
	local lastPressPosition = Vector2.zero
	local savingToShown, savingToToken = nil, 0
	api.rowsById = rowsById
	api.visualItems = visualItems

	-- "Saving to" pops up when the target folder changes, then clears after a few seconds.
	local function showSavingTo(text)
		if text == savingToShown then
			return
		end
		savingToShown = text
		savingToToken += 1
		local token = savingToToken
		savingToLabel.Text = text
		task.delay(4, function()
			if savingToToken == token then
				savingToLabel.Text = ""
			end
		end)
	end

	function api.resetSavingTo()
		savingToShown = nil
	end

	local function saveIndex()
		plugin:SetSetting(SETTING.savedIndex, savedIndex)
	end

	local function findSaved(id)
		for i, entry in savedIndex.npcs do
			if entry.id == id then
				return entry, i
			end
		end
		return nil
	end
	api.findSaved = findSaved

	local function findFolder(id)
		for i, folder in savedIndex.folders do
			if folder.id == id then
				return folder, i
			end
		end
		return nil
	end

	local function indexOf(list, item)
		for i, value in list do
			if value == item then
				return i
			end
		end
		return nil
	end

	local function encodeModel(model)
		-- Save a copy whose accessory welds match where the accessories actually sit.
		local copy = model:Clone()
		if not copy then
			error("this NPC can't be copied (its Archivable property is off)")
		end
		api.syncAccessoryWelds(copy)
		local raw = SerializationService:SerializeInstancesAsync({ copy })
		copy:Destroy()
		local packed = EncodingService:CompressBuffer(raw, Enum.CompressionAlgorithm.Zstd, 9)
		return buffer.tostring(EncodingService:Base64Encode(packed))
	end

	local function decodeModel(text)
		local packed = EncodingService:Base64Decode(buffer.fromstring(text))
		local raw = EncodingService:DecompressBuffer(packed, Enum.CompressionAlgorithm.Zstd)
		return SerializationService:DeserializeInstancesAsync(raw)[1]
	end
	api.encodeModel, api.decodeModel = encodeModel, decodeModel

	local function loadSavedModel(entry)
		if modelCache[entry.id] then
			return modelCache[entry.id]
		end
		local data = plugin:GetSetting(SETTING.savedNpcPrefix .. entry.id)
		if type(data) ~= "string" then
			return nil
		end
		local ok, model = pcall(decodeModel, data)
		if ok and model then
			modelCache[entry.id] = model
			return model
		end
		warn("[Catalog Loader V2] Couldn't load saved NPC", entry.name, model)
		return nil
	end
	api.loadSavedModel = loadSavedModel

	-- The saved copy of an NPC with this name, if any (Fix uses it as a reference).
	function api.findSavedModel(name)
		for _, entry in savedIndex.npcs do
			if entry.name == name then
				return loadSavedModel(entry)
			end
		end
		return nil
	end

	local function formatStamp(t)
		if type(t) ~= "number" then
			return nil
		end
		return os.date("%b %d, %Y", t) .. "\n" .. (os.date("%I:%M %p", t):gsub("^0", ""))
	end

	-- 3D preview -----------------------------------------------------------

	local previewModel = nil
	local previewAngle = 0
	local previewDragging = false
	local FACING_CAMERA = CFrame.lookAt(Vector3.zero, Vector3.new(0, 0, 1))

	local function showPreview(entry)
		if previewModel then
			previewModel:Destroy()
			previewModel = nil
		end
		previewName.Text = entry and entry.name or ""
		previewHint.Text = entry and "Loading..." or "Select a saved NPC to preview it in 3D"
		previewHint.Visible = true
		if not entry then
			return
		end
		task.spawn(function()
			local template = loadSavedModel(entry)
			if selectedId ~= entry.id then
				return
			end
			if not template then
				previewHint.Text = "Couldn't load this NPC"
				return
			end
			previewHint.Visible = false
			local model = template:Clone()
			previewAngle = 0
			model:PivotTo(FACING_CAMERA)
			local boxCf, size = model:GetBoundingBox()
			local fit = math.max(size.Y, math.max(size.X, size.Z) * 0.8) * 0.5
			local distance = fit / math.tan(math.rad(previewCamera.FieldOfView / 2)) * 1.15
			local center = boxCf.Position
			previewCamera.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.08, distance), center)
			model.Parent = previewWorld
			previewModel = model
		end)
	end

	-- Spin like the avatar editor; drag on the preview to turn it by hand.
	function api.stepPreview(dt)
		if not previewModel or not savePanel.Visible then
			return
		end
		if not previewDragging then
			previewAngle += dt * 0.9
		end
		previewModel:PivotTo(CFrame.Angles(0, previewAngle, 0) * FACING_CAMERA)
	end

	function api.getPreview()
		return previewModel, previewAngle
	end

	previewBg.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		local lastX = input.Position.X
		previewDragging = true
		beginDrag(input, function(pos)
			previewAngle += (pos.X - lastX) * 0.012
			lastX = pos.X
		end, function()
			previewDragging = false
		end, true)
	end)

	-- Selection, rename, delete ---------------------------------------------

	local function setActionsEnabled(enabled)
		for _, button in { spawnSavedButton, renameSavedButton } do
			button.TextTransparency = enabled and 0 or 0.55
		end
	end

	local function selectSaved(id)
		selectedId = id
		local entry = id and findSaved(id)
		if entry then
			activeFolderId = entry.folder
		end
		api.refreshSavedList()
		showPreview(entry)
	end
	api.selectSaved = selectSaved

	function api.getSelectedId()
		return selectedId
	end

	local function inlineRename(row, label, current, onCommit)
		label.Visible = false
		local x = label.Position.X.Offset
		local box = textBox({
			Size = UDim2.new(1, -(x + 4), 1, -8),
			Position = UDim2.fromOffset(x - 6, 4),
			Text = current,
			TextSize = 17,
			ZIndex = 5,
			Parent = row,
		})
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #current + 1
		box.FocusLost:Connect(function()
			local name = trim(box.Text)
			if name ~= "" and name ~= current then
				onCommit(name)
			end
			api.refreshSavedList()
		end)
	end

	local function renameItem(kind, item)
		local refs = rowsById[item.id]
		if not refs then
			return
		end
		inlineRename(refs.row, refs.label, item.name, function(name)
			item.name = name
			if kind == "npc" and item.id == selectedId then
				previewName.Text = name
			end
			saveIndex()
		end)
	end
	api.renameItem = renameItem

	local function removeFrom(list, item)
		local index = indexOf(list, item)
		if index then
			table.remove(list, index)
		end
	end

	local function deleteItem(kind, item)
		if kind == "npc" then
			plugin:SetSetting(SETTING.savedNpcPrefix .. item.id, nil)
			removeFrom(savedIndex.npcs, item)
			if modelCache[item.id] then
				modelCache[item.id]:Destroy()
				modelCache[item.id] = nil
			end
			if selectedId == item.id then
				selectedId = nil
				showPreview(nil)
			end
		else
			-- Deleting a folder keeps its NPCs; they move back to Unsorted.
			removeFrom(savedIndex.folders, item)
			for _, entry in savedIndex.npcs do
				if entry.folder == item.id then
					entry.folder = nil
				end
			end
			if activeFolderId == item.id then
				activeFolderId = nil
			end
		end
		saveIndex()
		api.refreshSavedList()
		setStatus("Deleted " .. item.name)
	end
	api.deleteItem = deleteItem

	local function spawnEntry(entry)
		if not workspace.CurrentCamera then
			return
		end
		setStatus("Spawning " .. entry.name .. "...")
		task.spawn(function()
			local template = loadSavedModel(entry)
			if not template then
				setStatus("Couldn't load " .. entry.name)
				return
			end
			local rig = api.prepareSpawn(template:Clone())
			rig.Name = entry.name
			withUndo("Spawn " .. entry.name, function()
				placeRigInFront(rig)
			end)
			api.rememberPose(rig, true)
			Selection:Set({ rig })
			setStatus("Spawned " .. entry.name .. " in front of you")
		end)
	end

	-- Re-saves an entry from the NPC selected in Studio, keeping its name, folder, color and date.
	local function updateEntry(entry)
		local rig = getTargets()[1]
		if not rig then
			setStatus("Select the NPC in Studio first, then choose Update from Selection.")
			return
		end
		task.spawn(function()
			local ok, data = pcall(encodeModel, rig)
			if not ok then
				warn("[Catalog Loader V2] Couldn't update", entry.name, data)
				setStatus("Couldn't update " .. entry.name .. " (see Output)")
				return
			end
			plugin:SetSetting(SETTING.savedNpcPrefix .. entry.id, data)
			api.rememberPose(rig, true)
			if modelCache[entry.id] then
				modelCache[entry.id]:Destroy()
				modelCache[entry.id] = nil
			end
			if selectedId == entry.id then
				showPreview(entry)
			end
			setStatus(("Updated %s from %s"):format(entry.name, rig.Name))
		end)
	end
	api.updateEntry = updateEntry

	local function changeColor(item, anchor)
		local before = item.color
		api.openColorPicker({
			anchor = anchor,
			title = "Change Color",
			targets = { { key = "color", label = "Color", color = before and Color3.fromHex(before) or COLORS.cell } },
			onChange = function(_, color)
				item.color = color:ToHex()
				api.refreshSavedList()
			end,
			onCommit = saveIndex,
			onCancel = function()
				item.color = before
				api.refreshSavedList()
			end,
		})
	end

	local function openContextMenu(kind, item, position)
		openPopup(position, item.name, function(list)
			local order = 0
			local function add(text, onClick, danger)
				order += 1
				return menuRow(list, order, text, onClick, danger)
			end
			if kind == "npc" then
				add("Spawn", function()
					closePopup()
					spawnEntry(item)
				end)
				add("Update from Selection", function()
					closePopup()
					updateEntry(item)
				end)
			end
			add("Rename", function()
				closePopup()
				renameItem(kind, item)
			end)
			add("Change Color", function()
				changeColor(item, position)
			end)
			if item.color then
				add("Reset Color", function()
					item.color = nil
					saveIndex()
					closePopup()
					api.refreshSavedList()
				end)
			end
			add(kind == "folder" and "Delete Folder" or "Delete", function(row, label)
				if row:GetAttribute("Armed") then
					closePopup()
					deleteItem(kind, item)
				else
					row:SetAttribute("Armed", true)
					label.Text = "Click again to delete"
				end
			end, true)
		end, { width = 230 })
	end

	-- Drag to reorder ---------------------------------------------------------

	local dropLine = create("Frame", {
		Name = "DropLine",
		BackgroundColor3 = "@accent",
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
		Parent = savePanel,
	}, { round() })

	local dropBox = create("Frame", {
		Name = "DropBox",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = savePanel,
	}, { corner(6), stroke("accent", 2) })

	local function showDropTarget(target)
		dropLine.Visible = false
		dropBox.Visible = false
		if not target then
			return
		end
		local origin = savePanel.AbsolutePosition
		if target.into then
			local row = target.row
			dropBox.Position = UDim2.fromOffset(row.AbsolutePosition.X - origin.X, row.AbsolutePosition.Y - origin.Y)
			dropBox.Size = UDim2.fromOffset(row.AbsoluteSize.X, row.AbsoluteSize.Y)
			dropBox.Visible = true
		elseif target.lineRow then
			local row = target.lineRow
			local y = target.lineAfter and (row.AbsolutePosition.Y + row.AbsoluteSize.Y + 1) or (row.AbsolutePosition.Y - 4)
			dropLine.Position = UDim2.fromOffset(row.AbsolutePosition.X - origin.X, y - origin.Y)
			dropLine.Size = UDim2.fromOffset(row.AbsoluteSize.X, 3)
			dropLine.Visible = true
		end
	end

	-- Works out where a dragged row would land for the mouse position `pos`.
	local function computeDrop(kind, item, pos)
		local last = visualItems[#visualItems]
		if not last then
			return nil
		end
		for _, vi in visualItems do
			local top, height = vi.row.AbsolutePosition.Y, vi.row.AbsoluteSize.Y
			if pos.Y < top + height then
				local lower = pos.Y > top + height / 2
				if kind == "npc" then
					if vi.kind == "folder" then
						return { into = vi.ref, row = vi.row }
					elseif vi.ref == item then
						return nil
					end
					return { folderId = vi.ref.folder, anchor = vi.ref, after = lower, lineRow = vi.row, lineAfter = lower }
				end
				-- Folders only move among folders; rows inside a folder count as part of its block.
				local folder = vi.kind == "folder" and vi.ref or (vi.ref.folder and findFolder(vi.ref.folder))
				if not folder then
					return { toEnd = true, lineRow = vi.row, lineAfter = false }
				elseif folder == item then
					return nil
				end
				local after = vi.kind ~= "folder" or lower
				return { anchor = folder, after = after, lineRow = after and folderBlockEnd[folder.id] or vi.row, lineAfter = after }
			end
		end
		if kind == "npc" then
			return { folderId = nil, lineRow = last.row, lineAfter = true }
		end
		return { toEnd = true, lineRow = last.row, lineAfter = true }
	end
	api.computeDrop = computeDrop

	local function applyDrop(kind, item, target)
		if kind == "npc" then
			local list = savedIndex.npcs
			removeFrom(list, item)
			if target.into then
				item.folder = target.into.id
				target.into.collapsed = false
				table.insert(list, item)
			else
				item.folder = target.folderId
				local index = target.anchor and indexOf(list, target.anchor)
				if index then
					table.insert(list, target.after and index + 1 or index, item)
				else
					table.insert(list, item)
				end
			end
			if item.id == selectedId then
				activeFolderId = item.folder
			end
		else
			local list = savedIndex.folders
			removeFrom(list, item)
			local index = not target.toEnd and target.anchor and indexOf(list, target.anchor)
			if index then
				table.insert(list, target.after and index + 1 or index, item)
			else
				table.insert(list, item)
			end
		end
		saveIndex()
		api.refreshSavedList()
	end
	api.applyDrop = applyDrop

	local function startRowDrag(kind, item, input)
		local start = Vector2.new(input.Position.X, input.Position.Y)
		local ghost, target = nil, nil
		beginDrag(input, function(pos)
			if not ghost then
				if (pos - start).Magnitude < 6 then
					return
				end
				suppressClickUntil = math.huge
				dragCatcher.Visible = true
				ghost = create("TextLabel", {
					Size = UDim2.fromOffset(SIDE_W - 50, 38),
					BackgroundColor3 = "@accent",
					Font = FONT_BOLD,
					Text = item.name,
					TextSize = 17,
					TextColor3 = "@onAccent",
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 96,
					Parent = screenGui,
				}, { corner(6), hpadding(12) })
				ghost.BackgroundTransparency = 0.15
			end
			ghost.Position = UDim2.fromOffset(pos.X + 14, pos.Y - 19)
			-- Scroll when dragging near the top or bottom of the list.
			local top = savedList.AbsolutePosition.Y
			local bottom = top + savedList.AbsoluteSize.Y
			if pos.Y < top + 28 then
				savedList.CanvasPosition = Vector2.new(0, math.max(0, savedList.CanvasPosition.Y - 12))
			elseif pos.Y > bottom - 28 then
				savedList.CanvasPosition += Vector2.new(0, 12)
			end
			target = computeDrop(kind, item, pos)
			showDropTarget(target)
		end, function()
			if not ghost then
				return
			end
			ghost:Destroy()
			showDropTarget(nil)
			suppressClickUntil = os.clock() + 0.25
			if target then
				applyDrop(kind, item, target)
			end
		end)
	end

	-- Rows -------------------------------------------------------------------

	local function itemRow(kind, item, order, indent, count)
		local isFolder = kind == "folder"
		local selected = not isFolder and item.id == selectedId
		local ok, custom = pcall(Color3.fromHex, item.color or "")
		custom = item.color and ok and custom or nil

		local row = create("TextButton", {
			Name = isFolder and "Folder" or "NPC",
			Size = UDim2.new(1, 0, 0, 46),
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = order,
			Parent = savedList,
		}, { corner(6) })

		local textColor
		if custom then
			row.BackgroundColor3 = custom
			row.BackgroundTransparency = uiTransparency
			local hoverColor = custom:Lerp(Color3.new(1, 1, 1), 0.15)
			row.MouseEnter:Connect(function()
				row.BackgroundColor3 = hoverColor
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundColor3 = custom
			end)
			if selected then
				stroke("accent", 2.5).Parent = row
			end
			textColor = luminance(custom) > 0.6 and Color3.fromRGB(30, 30, 30) or Color3.new(1, 1, 1)
		else
			local role = selected and "accent" or isFolder and "popup" or "cell"
			bindColor(row, "BackgroundColor3", role)
			if not selected then
				hover(row, role, isFolder and "buttonHover" or "cellHover")
			end
		end

		local x = indent + 12
		if isFolder then
			if item.id == activeFolderId then
				create("Frame", {
					Size = UDim2.new(0, 4, 1, -12),
					Position = UDim2.fromOffset(3, 6),
					BackgroundColor3 = "@accent",
					BorderSizePixel = 0,
					Parent = row,
				}, { corner(2) })
			end
			local arrow = chevron(row, UDim2.new(0, indent + 18, 0.5, 0))
			arrow.Rotation = item.collapsed and -90 or 0
			x = indent + 34
		end

		local label = create("TextLabel", {
			Size = UDim2.new(1, -(x + 118), 1, 0),
			Position = UDim2.fromOffset(x, 0),
			BackgroundTransparency = 1,
			Font = (isFolder or selected) and FONT_BOLD or FONT,
			Text = isFolder and ("%s (%d)"):format(item.name, count) or item.name,
			TextSize = 18,
			TextColor3 = textColor or (selected and "@onAccent" or "@text"),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		local stamp = formatStamp(isFolder and item.createdAt or item.savedAt)
		if stamp then
			create("TextLabel", {
				Size = UDim2.fromOffset(108, 38),
				Position = UDim2.new(1, -10, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = stamp,
				TextSize = 14,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.55,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end

		onLeftClick(row, function()
			if os.clock() < suppressClickUntil then
				return
			end
			-- A second click on the same row opens its menu (Studio keeps right-click for itself).
			-- Rows are rebuilt on every click, so the double click is matched by item, not by row.
			local now = os.clock()
			if lastClick and lastClick.id == item.id and now - lastClick.time < DOUBLE_CLICK then
				if isFolder then
					item.collapsed = lastClick.collapsed
					saveIndex()
					api.refreshSavedList()
				end
				lastClick = nil
				openContextMenu(kind, item, lastPressPosition)
				return
			end
			lastClick = { id = item.id, time = now, collapsed = item.collapsed }
			if isFolder then
				if activeFolderId == item.id then
					item.collapsed = not item.collapsed
				else
					activeFolderId = item.id
					item.collapsed = false
				end
				saveIndex()
				api.refreshSavedList()
			else
				selectSaved(item.id)
			end
		end)
		row.InputBegan:Connect(function(input)
			if isPress(input) then
				lastPressPosition = Vector2.new(input.Position.X, input.Position.Y)
				startRowDrag(kind, item, input)
			end
		end)
		row.InputEnded:Connect(endDrag)

		rowsById[item.id] = { row = row, label = label }
		table.insert(visualItems, { kind = kind, ref = item, row = row })
		return row
	end

	function api.refreshSavedList()
		for _, child in savedList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(rowsById)
		table.clear(visualItems)
		table.clear(folderBlockEnd)

		local active = activeFolderId and findFolder(activeFolderId)
		if activeFolderId and not active then
			activeFolderId = nil
		end
		showSavingTo("Saving to: " .. (active and active.name or "Unsorted"))

		-- With a search, only matching NPCs and folders show; a folder holding a matching NPC is
		-- shown and opened so the NPC is visible.
		local query = trim(savedSearch.Text):lower()
		local function matches(name)
			return query == "" or string.find(name:lower(), query, 1, true) ~= nil
		end
		local opened = false

		local order = 0
		for _, folder in savedIndex.folders do
			local members, shown = {}, {}
			for _, entry in savedIndex.npcs do
				if entry.folder == folder.id then
					table.insert(members, entry)
					if matches(entry.name) then
						table.insert(shown, entry)
					end
				end
			end
			if matches(folder.name) then
				shown = members
			end
			if query == "" or #shown > 0 or matches(folder.name) then
				if query ~= "" and #shown > 0 and folder.collapsed and not matches(folder.name) then
					folder.collapsed = false
					opened = true
				end
				order += 1
				local last = itemRow("folder", folder, order, 0, #members)
				if not folder.collapsed then
					for _, entry in shown do
						order += 1
						last = itemRow("npc", entry, order, 20)
					end
				end
				folderBlockEnd[folder.id] = last
			end
		end
		for _, entry in savedIndex.npcs do
			if not entry.folder or not findFolder(entry.folder) then
				entry.folder = nil
				if matches(entry.name) then
					order += 1
					itemRow("npc", entry, order, 0)
				end
			end
		end
		if opened then
			saveIndex()
		end

		if order == 0 then
			create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundTransparency = 1,
				Font = FONT,
				Text = query ~= "" and ('Nothing matches "' .. trim(savedSearch.Text) .. '".')
					or "No saved NPCs yet. Select an NPC in Studio and click Save NPC.",
				TextSize = 15,
				TextColor3 = "@subtext",
				TextWrapped = true,
				Parent = savedList,
			})
		end
		setActionsEnabled(selectedId ~= nil and findSaved(selectedId) ~= nil)
	end

	savedSearch:GetPropertyChangedSignal("Text"):Connect(function()
		api.refreshSavedList()
	end)

	-- Buttons ----------------------------------------------------------------

	function api.saveSelectedNpcs()
		local rigs = getTargets()
		if #rigs == 0 then
			setStatus("Select an NPC in Studio, then click Save NPC.")
			return
		end
		setStatus("Saving...")
		task.spawn(function()
			local lastId, saved = nil, 0
			for _, rig in rigs do
				local ok, data = pcall(encodeModel, rig)
				if ok then
					api.rememberPose(rig, true)
					local id = HttpService:GenerateGUID(false)
					plugin:SetSetting(SETTING.savedNpcPrefix .. id, data)
					table.insert(savedIndex.npcs, { id = id, name = rig.Name, folder = activeFolderId, savedAt = os.time() })
					lastId = id
					saved += 1
				else
					warn("[Catalog Loader V2] Couldn't save", rig:GetFullName(), data)
				end
			end
			saveIndex()
			if lastId then
				selectSaved(lastId)
			end
			if saved == #rigs then
				setStatus(saved == 1 and ("Saved " .. rigs[1].Name) or ("Saved " .. saved .. " NPCs"))
			else
				setStatus(("Saved %d of %d NPCs (see Output for errors)"):format(saved, #rigs))
			end
		end)
	end

	function api.createFolder()
		local taken = {}
		for _, folder in savedIndex.folders do
			taken[folder.name] = true
		end
		local name, n = "New Folder", 1
		while taken[name] do
			n += 1
			name = "New Folder " .. n
		end
		local folder = { id = HttpService:GenerateGUID(false), name = name, collapsed = false, createdAt = os.time() }
		table.insert(savedIndex.folders, folder)
		activeFolderId = folder.id
		saveIndex()
		api.refreshSavedList()
		renameItem("folder", folder)
		return folder
	end

	onLeftClick(saveNpcButton, api.saveSelectedNpcs)
	onLeftClick(newFolderButton, api.createFolder)
	onLeftClick(spawnSavedButton, function()
		local entry = selectedId and findSaved(selectedId)
		if entry then
			spawnEntry(entry)
		end
	end)
	onLeftClick(renameSavedButton, function()
		local entry = selectedId and findSaved(selectedId)
		if entry then
			renameItem("npc", entry)
		end
	end)
end

---------------------------------------------------------------------------
-- Settings: themes, custom colors, transparency, spawning options
---------------------------------------------------------------------------

do
	local themeListOpen = false

	function api.applyTheme(theme, preview)
		loadThemeColors(theme)
		for inst, props in themed do
			for prop, role in props do
				applyRole(inst, prop, role)
			end
		end
		api.setCherryDecor(theme.cherry == true)
		api.refreshFilterButtons()
		api.refreshSavedList()
		if not preview then
			plugin:SetSetting(SETTING.theme, themeKey(theme))
		end
	end

	function api.setTransparency(value)
		uiTransparency = math.clamp(value, 0, MAX_TRANSPARENCY)
		for inst, props in themed do
			local role = props.BackgroundColor3
			if role and SURFACE_ROLES[role] then
				inst.BackgroundTransparency = uiTransparency
			end
		end
	end

	local function saveCustomThemes()
		plugin:SetSetting(SETTING.customThemes, customThemes)
	end

	-- Custom theme names must not clash with the built-in themes or each other.
	local function uniqueThemeName(name, record)
		name = name ~= "" and name or "My Theme"
		local taken = {}
		for _, theme in THEMES do
			taken[theme.name:lower()] = true
		end
		for _, other in customThemes do
			if other ~= record then
				taken[other.name:lower()] = true
			end
		end
		local candidate, n = name, 1
		while taken[candidate:lower()] do
			n += 1
			candidate = ("%s %d"):format(name, n)
		end
		return candidate
	end

	-- Opens the color picker for a new custom theme (record == nil) or one the user made.
	-- The built-in themes are never changed.
	local function editCustomTheme(record)
		local before = currentTheme
		local base = record and customTheme(record) or currentTheme
		local draft = { bg = base.colors.panel, accent = base.colors.accent, text = base.colors.text }
		api.openColorPicker({
			anchor = settingsButton,
			title = record and "Edit Theme" or "New Custom Theme",
			name = record and record.name or uniqueThemeName("My Theme"),
			targets = {
				{ key = "bg", label = "Background", color = draft.bg },
				{ key = "accent", label = "Buttons", color = draft.accent },
				{ key = "text", label = "Text", color = draft.text },
			},
			onChange = function(key, color)
				draft[key] = color
				api.applyTheme(deriveTheme(draft.bg, draft.accent, draft.text), true)
			end,
			onCommit = function(name)
				if not record then
					record = { id = HttpService:GenerateGUID(false) }
					table.insert(customThemes, record)
				end
				record.name = uniqueThemeName(name or "", record)
				record.bg, record.accent, record.text = draft.bg:ToHex(), draft.accent:ToHex(), draft.text:ToHex()
				saveCustomThemes()
				api.applyTheme(customTheme(record))
				themeListOpen = true
				api.openSettings()
			end,
			onCancel = function()
				api.applyTheme(before, true)
			end,
		})
	end
	api.editCustomTheme = editCustomTheme

	local function renameCustomTheme(record)
		openPopup(settingsButton, "Rename Theme", function(list)
			local box = popupTextBox(list, 1, "Theme name", record.name)
			popupApply(list, 2, function()
				record.name = uniqueThemeName(trim(box.Text), record)
				saveCustomThemes()
				api.applyTheme(customTheme(record))
				api.openSettings()
			end)
		end, { width = 300 })
	end

	local function deleteCustomTheme(record)
		local index = table.find(customThemes, record)
		if index then
			table.remove(customThemes, index)
		end
		saveCustomThemes()
		if currentTheme.record == record then
			api.applyTheme(THEMES[1])
		end
		api.openSettings()
	end
	api.deleteCustomTheme = deleteCustomTheme

	-- GitHub's copy of the plugin, kept when its VERSION is newer than this one. Checked once at startup.
	local update = nil -- { version = "2.0.3", source = "..." }
	local updateInstalled = false -- downloaded this session; it runs once Studio restarts
	task.spawn(function()
		local ok, source = pcall(HttpService.GetAsync, HttpService, UPDATE_URL, true)
		if not ok then
			return
		end
		local version = string.match(source, '\nlocal VERSION = "(%d+%.%d+%.%d+)"')
		if version and isNewerVersion(version, VERSION) then
			update = { version = version, source = source }
		end
	end)

	function api.openSettings()
		local settingsPopup = openPopup(settingsButton, "Settings", function(list)
			local order = 0
			local function nextOrder()
				order += 1
				return order
			end

			popupLabel(list, nextOrder(), "Theme")
			-- Dropdown showing the current theme; click to show every theme.
			local holder = create("Frame", {
				Size = UDim2.new(1, -6, 0, 46),
				BackgroundTransparency = 1,
				LayoutOrder = nextOrder(),
				Parent = list,
			}, { hpadding(8) })
			local dropdown = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.fromOffset(0, 3),
				BackgroundColor3 = "@cell",
				AutoButtonColor = false,
				Text = "",
				Parent = holder,
			}, { corner(6), stroke() })
			hover(dropdown, "cell", "cellHover")
			themeSwatch(dropdown, currentTheme, UDim2.new(0, 22, 0.5, 0))
			create("TextLabel", {
				Size = UDim2.new(1, -80, 1, 0),
				Position = UDim2.fromOffset(44, 0),
				BackgroundTransparency = 1,
				Font = FONT_BOLD,
				Text = currentTheme.name,
				TextSize = 16,
				TextColor3 = "@text",
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = dropdown,
			})
			chevron(dropdown, UDim2.new(1, -20, 0.5, 0)).Rotation = themeListOpen and 180 or 0
			onLeftClick(dropdown, function()
				themeListOpen = not themeListOpen
				api.openSettings()
			end)

			if themeListOpen then
				for _, theme in themeList() do
					radioRow(list, nextOrder(), theme.name, themeKey(theme) == themeKey(currentTheme), true, function()
						api.applyTheme(theme)
						api.openSettings()
					end, theme)
				end
			end

			-- Only themes the user made can be edited, renamed or deleted.
			local record = currentTheme.record
			if record then
				local row = create("Frame", {
					Size = UDim2.new(1, -6, 0, 44),
					BackgroundTransparency = 1,
					LayoutOrder = nextOrder(),
					Parent = list,
				}, {
					hpadding(8),
					create("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				})
				local function themeAction(text, order, onClick)
					local button = secondaryButton({
						Size = UDim2.new(1 / 3, -4, 0, 36),
						Text = text,
						TextSize = 14,
						LayoutOrder = order,
						Parent = row,
					})
					onLeftClick(button, function()
						onClick(button)
					end)
				end
				themeAction("Edit Colors", 1, function()
					editCustomTheme(record)
				end)
				themeAction("Rename", 2, function()
					renameCustomTheme(record)
				end)
				themeAction("Delete", 3, function(button)
					if button:GetAttribute("Armed") then
						deleteCustomTheme(record)
					else
						button:SetAttribute("Armed", true)
						button.Text = "Sure?"
						bindColor(button, "BackgroundColor3", "bad")
					end
				end)
			end
			popupButton(list, nextOrder(), "+ New Custom Theme", function()
				editCustomTheme(nil)
			end)

			local transparencyLabel = popupLabel(list, nextOrder(), "")
			local function showTransparency()
				transparencyLabel.Text = ("UI Transparency: %d%%"):format(math.floor(uiTransparency * 100 + 0.5))
			end
			showTransparency()
			sliderRow(list, nextOrder(), uiTransparency / MAX_TRANSPARENCY, function(fraction)
				api.setTransparency(fraction * MAX_TRANSPARENCY)
				showTransparency()
			end, function()
				plugin:SetSetting(SETTING.transparency, uiTransparency)
				api.refreshSavedList()
			end)

			popupLabel(list, nextOrder(), "NPC Spawning")
			toggleRow(list, nextOrder(), "Spawn with NPC Label", spawnWithLabel, function(on)
				spawnWithLabel = on
				plugin:SetSetting(SETTING.spawnWithLabel, on)
			end)

			-- Only shown while GitHub has a newer version than the one running.
			if update then
				local restartText = "Restart Studio to use V" .. update.version
				local updateButton
				updateButton = popupButton(list, nextOrder(), updateInstalled and restartText or ("Update to V" .. update.version), function()
					if updateInstalled then
						setStatus(restartText)
						return
					end
					updateButton.Text = "Updating..."
					local run, err = compileUpdate(update.source)
					if not run then
						updateButton.Text = "Update to V" .. update.version
						setStatus("Update failed: " .. tostring(err))
						return
					end
					plugin:SetSetting(UPDATE_SETTINGS.source, update.source)
					plugin:SetSetting(UPDATE_SETTINGS.version, update.version)
					updateInstalled = true
					updateButton.Text = restartText
					setStatus("Updated to V" .. update.version .. "! Restart Studio to use the new version.")
					print("[Catalog Loader V2] Updated to V" .. update.version .. ". Restart Studio to use the new version.")
				end)
			end
		end, { width = 300, maxHeight = 700 })

		create("TextLabel", {
			Name = "Credit",
			Size = UDim2.fromOffset(160, 36),
			Position = UDim2.new(1, -14, 0, 4),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = "Created by Elaine",
			TextSize = 18,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = settingsPopup,
		})
	end

	onLeftClick(settingsButton, api.openSettings)
end

---------------------------------------------------------------------------
-- Window: dragging, resizing, minimize, close
---------------------------------------------------------------------------

local function setPanelPosition(x, y)
	local screen = screenGui.AbsoluteSize
	if screen.X > 0 and screen.Y > 0 then
		local minX = sideOpen and (SIDE_W + SIDE_GAP) or 0
		x = math.clamp(x, minX, math.max(minX, screen.X - main.AbsoluteSize.X))
		y = math.clamp(y, 0, math.max(0, screen.Y - TITLE_H))
	end
	main.Position = UDim2.fromOffset(x, y)
end

local function setPanelSize(w, h)
	local screen = screenGui.AbsoluteSize
	local pos = main.AbsolutePosition
	local maxW = screen.X > 0 and math.max(MIN_W, screen.X - pos.X) or w
	local maxH = screen.Y > 0 and math.max(MIN_H, screen.Y - pos.Y) or h
	main.Size = UDim2.fromOffset(math.clamp(w, MIN_W, maxW), math.clamp(h, MIN_H, maxH))
end

local function setSideOpen(open)
	sideOpen = open
	if open then
		api.resetSavingTo()
		api.refreshSavedList()
		setPanelPosition(main.Position.X.Offset, main.Position.Y.Offset)
	end
	syncSidePanel()
end

onLeftClick(saveButton, function()
	setSideOpen(not sideOpen)
end)

local function savePanelPosition()
	plugin:SetSetting(SETTING.panelPosition, { main.Position.X.Offset, main.Position.Y.Offset })
end

titleBar.InputBegan:Connect(function(input)
	if not isPress(input) then
		return
	end
	for _, button in { closeButton, minimizeButton, settingsButton } do
		if isOver(button, input.Position) then
			return
		end
	end
	closePopup()
	local start = Vector2.new(input.Position.X, input.Position.Y)
	local startPos = Vector2.new(main.Position.X.Offset, main.Position.Y.Offset)
	beginDrag(input, function(pos)
		setPanelPosition(startPos.X + pos.X - start.X, startPos.Y + pos.Y - start.Y)
	end, savePanelPosition, true)
end)

for _, handle in resizeHandles do
	handle.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		closePopup()
		local start = Vector2.new(input.Position.X, input.Position.Y)
		local startSize = main.AbsoluteSize
		local axis = Vector2.new(handle:GetAttribute("AxisX"), handle:GetAttribute("AxisY"))
		beginDrag(input, function(pos)
			setPanelSize(startSize.X + (pos.X - start.X) * axis.X, startSize.Y + (pos.Y - start.Y) * axis.Y)
		end, nil, true)
	end)
end

local expandedSize = main.Size

local function setMinimized(value)
	if value == minimized then
		return
	end
	minimized = value
	closePopup()
	if minimized then
		expandedSize = main.Size
		main.Size = UDim2.fromOffset(main.AbsoluteSize.X, TITLE_H)
	else
		main.Size = expandedSize
	end
	content.Visible = not minimized
	for _, handle in resizeHandles do
		handle.Visible = not minimized
	end
	minimizeIcon.Visible = not minimized
	restoreIcon.Visible = minimized
	syncSidePanel()
end

onLeftClick(minimizeButton, function()
	setMinimized(not minimized)
end)

---------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Catalog Loader V2")
local toggleButton = toolbar:CreateButton(
	"CatalogLoaderV2",
	"Browse the Marketplace and import items onto selected NPCs",
	ICON,
	"Catalog Loader V2"
)
toggleButton.ClickableWhenViewportHidden = true

local hasSearched = false

local function setOpen(open)
	if not open then
		-- Closing resets the panel to its default size.
		closePopup()
		setMinimized(false)
		setSideOpen(false)
		main.Size = UDim2.fromOffset(DEFAULT_W, DEFAULT_H)
	end
	screenGui.Enabled = open
	toggleButton:SetActive(open)
	if open then
		local screen = screenGui.AbsoluteSize
		main.Size = UDim2.fromOffset(math.min(DEFAULT_W, math.max(MIN_W, screen.X)), math.min(DEFAULT_H, math.max(MIN_H, screen.Y)))
		local saved = plugin:GetSetting(SETTING.panelPosition)
		if type(saved) == "table" and saved[1] and saved[2] then
			setPanelPosition(saved[1], saved[2])
		else
			setPanelPosition((screen.X - DEFAULT_W) / 2, (screen.Y - DEFAULT_H) / 2)
		end
		relayout()
		syncSidePanel()
		updateTargetLabel()
		if not hasSearched then
			hasSearched = true
			startSearch()
		end
	end
end
api.setOpen = setOpen
api.setSideOpen = setSideOpen
api.setMinimized = setMinimized
api.setPanelSize = setPanelSize

toggleButton.Click:Connect(function()
	setOpen(not screenGui.Enabled)
end)

onLeftClick(closeButton, function()
	setOpen(false)
end)

local elapsed = 0
local connections = {
	rightReleaseConnection,
	UserInputService.InputChanged:Connect(updateDrag),
	UserInputService.InputEnded:Connect(endDrag),
	Selection.SelectionChanged:Connect(function()
		api.rememberSelectedRigs()
		if screenGui.Enabled then
			updateTargetLabel()
		end
	end),
	RunService.Heartbeat:Connect(function(dt)
		if not screenGui.Enabled then
			return
		end
		elapsed += dt
		api.stepPreview(dt)
		if currentTheme.cherry then
			api.stepPetals(dt, elapsed)
		end
	end),
}

api.refreshSavedList()
-- Remember every NPC in the place that looks put together, so Fix has something to go back to.
task.defer(api.rememberAll)

plugin.Unloading:Connect(function()
	for _, connection in connections do
		connection:Disconnect()
	end
	for _, model in api.modelCache do
		model:Destroy()
	end
	api.destroyColorWheel()
	screenGui:Destroy()
end)
