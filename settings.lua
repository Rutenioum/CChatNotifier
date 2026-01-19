local _addonName, _addon = ...;
local L = _addon:GetLocalization();

local DEFAULTSETTINGS = {
    ["firstStart"] = true,
    ["isActive"] = true,
    ["chatFrame"] = 1,
    ["soundId"] = "sound/interface/itellmessage.ogg",
    ["showMinimapButton"] = true,
    ["snapToMinimap"] = true,
    ["outputFormat"] = "", -- fill from localization
    ["version"] = GetAddOnMetadata(_addonName, "Version"),
    ["antiSpamWindow"] = 45,
    ["classColor"] = true,
};

local SOUNDS = {
    [""] = L["SOUND_NO_SOUND"],
    ["sound/Doodad/LightHouseFogHorn.ogg"] = "Fog horn", 		                    -- 567094
    ["sound/interface/itellmessage.ogg"] = "Whisper", 		                        -- 567421
    ["sound/character/dwarf/dwarfmale/dwarfmaledeatha.ogg"] = "Dwarf", 		        -- 539885
    ["sound/item/weapons/bow/arrowhitc.ogg"] = "Something", 	                    -- 567671
    ["sound/item/weapons/bow/arrowhita.ogg"] = "Something2",                        -- 567672
    ["sound/item/weapons/axe2h/m2haxehitmetalweaponcrit.ogg"] = "Hurts my ears"     -- 567653
};

--- Handle stuff after settings changed, if needed
--- 如果需要，在更改settings后处理东西
local function AfterSettingsChange()
    _addon:MinimapButtonUpdate();
    if CChatNotifier_settings.snapToMinimap then
        _addon:MinimapButtonSnap();
    end
end

--- Extract color code
local function extractColors(format, text)
    local i = string.find(format, text)
    if i and i > 7 and string.sub(format, i-1, i-1) == ">" then
        if string.sub(format, i-2, i-2) =="<" then
            return "|r"
        else
            return "|cff" .. string.sub(format, i-7, i-2)
        end
    end
    return "|r"
end

--- Setup SV tables, check settings and setup settings menu
--- Setup SV tables, check settings and setup settings menu
function _addon:SetupSettings()
    -- 初始化数据存储表（用于存储监控规则）
	if CChatNotifier_data == nil then
		CChatNotifier_data = {};
	end
    
    -- 初始化设置存储表（从默认设置深拷贝）
    if CChatNotifier_settings == nil then
		CChatNotifier_settings = DEFAULTSETTINGS;
	end
    
    -- 合并默认设置到当前设置（补全缺失项）
	for k, v in pairs(DEFAULTSETTINGS) do
		if CChatNotifier_settings[k] == nil then
			CChatNotifier_settings[k] = v;
		end
	end
    
    -- 清理无效设置项（移除不在默认设置中的键）
	for k, v in pairs(CChatNotifier_settings) do
		if DEFAULTSETTINGS[k] == nil then
			CChatNotifier_settings[k] = nil;
		end
	end

    -- 创建设置界面画布
    local settings = _addon:GetSettingsBuilder();
    settings:Setup(CChatNotifier_settings, DEFAULTSETTINGS, nil, [[Interface\AddOns\CChatNotifier\img\logos]], 192, 48, nil, 16);
    settings:SetAfterSaveCallback(AfterSettingsChange);  -- 设置保存后的回调函数

    -- 通用设置分组标题
    settings:MakeHeading(L["SETTINGS_HEAD_GENERAL"]);

    -- 聊天框选择下拉菜单（核心问题组件）
    settings:MakeDropdown("chatFrame", L["SETTINGS_CHATFRAME"], L["SETTINGS_CHATFRAME_TT"], 100, function() 
        -- 生成有效聊天窗口列表（过滤隐藏/未停靠的窗口）
        local chatWindows = {};
        for i = 1, NUM_CHAT_WINDOWS, 1 do
            local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i);
            if name ~= "" and (shown or docked)  then  -- 仅显示可见或已停靠的窗口
                chatWindows[i] = name;
            end
        end
        return chatWindows;
    end, 138);  -- 138为标签宽度

    -- 音效选择下拉菜单
    settings:MakeDropdown("soundId", L["SETTINGS_SOUNDID"], L["SETTINGS_SOUNDID_TT"], 100, function() 
        return SOUNDS;  -- 返回预定义的音效表
    end, 138);

    -- 第一行：小地图相关设置
    local row = settings:MakeSettingsRow();
    settings:MakeCheckboxOption("showMinimapButton", L["SETTINGS_MINIMAP"], L["SETTINGS_MINIMAP_TT"], row);  -- 显示小地图按钮
    settings:MakeCheckboxOption("snapToMinimap", L["SETTINGS_SNAP_MINIMAP"], L["SETTINGS_SNAP_MINIMAP_TT"], row);  -- 吸附到小地图
    settings:MakeCheckboxOption("classColor", L["Sender Class Color"], L["Set if color the sender's name by class"], row)  -- 按职业着色发送者名称

    -- 消息格式分组标题
    settings:MakeHeading(L["SETTINGS_HEAD_FORMAT"]);
    settings:MakeStringRow(L["SETTINGS_FORMAT_DESC"], "LEFT");  -- 格式说明文本

    -- 消息格式编辑框（带实时预览）
    local formatEdit = settings:MakeEditBoxOption("outputFormat", nil, 200, false, nil, nil, 0, nil);
    local prevString = settings:MakeStringRow();
    formatEdit:SetScript("OnTextChanged", function(self) 
        -- 实时预览格式修改效果
        local oldFormat = CChatNotifier_settings.outputFormat;
        CChatNotifier_settings.outputFormat = formatEdit:GetText();
        local preview = _addon:FormNotifyMsg("mankrik", "1. General", GetUnitName("player"), "LFM mankriks wife exploration team!", 5, 11);
        prevString:SetText(preview);
        CChatNotifier_settings.outputFormat = oldFormat;  -- 恢复原始格式
        
        -- 提取颜色代码（用于高亮关键词）
        CChatNotifier_settings.mscolor = extractColors(CChatNotifier_settings.outputFormat, "{MS}")
        CChatNotifier_settings.mfcolor = extractColors(CChatNotifier_settings.outputFormat, "{MF}")
        CChatNotifier_settings.mecolor = extractColors(CChatNotifier_settings.outputFormat, "{ME}")
        CChatNotifier_settings.sendercolor = extractColors(CChatNotifier_settings.outputFormat, "%[{P}%]")
    end);

    -- 第二行：测试和重置按钮
    row = settings:MakeSettingsRow();
    settings:MakeButton(L["SETTINGS_TEST_CHAT"], function() 
        -- 临时修改设置进行预览测试
        local oldSound = CChatNotifier_settings.soundId;
        local oldFormat = CChatNotifier_settings.outputFormat;
        CChatNotifier_settings.outputFormat = formatEdit:GetText();
        
        -- 更新颜色代码提取
        CChatNotifier_settings.mscolor = extractColors(CChatNotifier_settings.outputFormat, "{MS}")
        CChatNotifier_settings.mfcolor = extractColors(CChatNotifier_settings.outputFormat, "{MF}")
        CChatNotifier_settings.mecolor = extractColors(CChatNotifier_settings.outputFormat, "{ME}")
        CChatNotifier_settings.sendercolor = extractColors(CChatNotifier_settings.outputFormat, "%[{P}%]")
        
        -- 发送测试消息到指定聊天框（使用全局chatFrame设置）
        _addon:PostNotification(_addon:FormNotifyMsg("mankrik", L["VICINITY"], GetUnitName("player"), 
            "LFM mankriks wife exploration team!", 5, 11), CChatNotifier_settings.chatFrame);
        
        -- 恢复原始设置
        CChatNotifier_settings.soundId = oldSound;
        CChatNotifier_settings.outputFormat = oldFormat;
        CChatNotifier_settings.mscolor = extractColors(CChatNotifier_settings.outputFormat, "{MS}")
        CChatNotifier_settings.mfcolor = extractColors(CChatNotifier_settings.outputFormat, "{MF}")
        CChatNotifier_settings.mecolor = extractColors(CChatNotifier_settings.outputFormat, "{ME}")
        CChatNotifier_settings.sendercolor = extractColors(CChatNotifier_settings.outputFormat, "%[{P}%]")
    end, row);

    -- 格式重置按钮
    settings:MakeButton(L["SETTINGS_FORMAT_RESET"], function() 
        CChatNotifier_settings.outputFormat = L["CHAT_NOTIFY_FORMAT"];  -- 重置为本地化默认格式
        formatEdit:SetText(CChatNotifier_settings.outputFormat);
        formatEdit:SetCursorPosition(0);  -- 光标复位
    end, row);

    -- 防刷屏时间窗口滑动条
    local antispam = settings:MakeSliderOption("antiSpamWindow",L["Antispam Window"],L["Set the time window for blocking spam message.(seconds)"], 0, 60, 1, row)
end