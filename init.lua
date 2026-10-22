local storage = core.get_mod_storage()
local player_attempts = {}
local player_verified = {}
local player_last_input = {}

local S = core.get_translator("twofactor_authentication")

local max_attempts = 2
local formspec_name_setup = "twofactor_authentication:setup"
local formspec_name_verify = "twofactor_authentication:verify"
local no_secret_marker = "no_secret_word"



local function hash_secret(secret)
    return core.sha1(secret)
end



local function has_secret(player_name)
    return storage:get_string(string.format("secret_%s", player_name)) ~= ""
end



local function wants_no_secret(player_name)
    return storage:get_string(string.format("secret_%s", player_name)) == no_secret_marker
end



local function save_secret(player_name, secret)
    storage:set_string(string.format("secret_%s", player_name), hash_secret(secret))
end



local function save_no_secret_choice(player_name)
    storage:set_string(string.format("secret_%s", player_name), no_secret_marker)
end



local function verify_secret(player_name, secret)
    return storage:get_string(string.format("secret_%s", player_name)) == hash_secret(secret)
end



local function get_secret_hint(player_name)
    return storage:get_string(string.format("hint_%s", player_name))
end



local function save_secret_hint(player_name, secret)
    if secret and #secret > 0 then
        local first_letter = secret:sub(1, 1)
        local hint = first_letter .. string.rep("*", #secret - 1)
        storage:set_string(string.format("hint_%s", player_name), hint)
    end
end



local function is_valid_secret(secret)
    if not secret or secret == "" then
        return false, S("Secret word cannot be empty")
    end
    if secret:match("^%s*$") then
        return false, S("Secret word cannot contain only spaces")
    end
    return true, ""
end



local function show_setup_formspec(player_name)
    local formspec = "formspec_version[4]" ..
        "size[12,7]" ..
        "allow_close[false]"..
        "label[0.5,0.5;" .. core.formspec_escape(S("Account Security Setup")) .. "]" ..
        "label[0.8,1.5;" .. core.formspec_escape(S("Create your secret word:")) .. "]" ..
        "field[0.8,2.2;4.5,0.8;secret_input;;]" ..
        "field_close_on_enter[secret_input;false]" ..
        "button[0.8,3.25;2,0.8;secret_submit;" .. core.formspec_escape(S("Create")) .. "]" ..
        "button[3,3.25;2.3,0.8;disconnect;" .. core.formspec_escape(S("Disconnect")) .. "]" ..
        "button[0.8,4.25;4.5,0.8;no_secret;" .. core.formspec_escape(S("I dont want secret word")) .. "]" ..
        "textarea[6.5,1.3;5,5;;;" ..
        core.formspec_escape(S("Welcome to the server!") .. "\n\n" ..
        S("Please create a secret word to secure your account.") .. "\n\n" ..
        S("This word is different from your password and adds extra protection.") .. "\n\n" ..
        S("You will be asked for this secret word each time you connect.")) ..
        "]"
    core.show_formspec(player_name, formspec_name_setup, formspec)
end



local function show_verify_formspec(player_name, error_message)
    local attempts_left = max_attempts - (player_attempts[player_name] or 0)
    local info_text = S("Identity Verification") .. "\n" ..
        S("Enter your secret word to access the server.") .. "\n\n" ..
        string.format(S("Attempts remaining: %d"), attempts_left) .. "\n\n" ..
        S("The secret words are all hashed, so no one can obtain them.") .. "\n\n" ..
        S("If you forgot your secret word, contact an administrator.")

    local hint_text = ""
    if player_attempts[player_name] and player_attempts[player_name] > 0 then
        local hint = get_secret_hint(player_name)
        if hint and hint ~= "" then
            hint_text = "\n" .. string.format(S("Hint: %s"), hint)
        end
    end

    local formspec = "formspec_version[4]" ..
        "size[12,7]" ..
        "allow_close[false]"..
        "label[0.75,0.5;" .. core.formspec_escape(S("Identity Verification")) .. "]" ..
        "field[0.8,2.2;4.5,0.8;secret_input;" .. core.formspec_escape(S("Enter your secret word:")) .. ";" .. 
        core.formspec_escape(player_last_input[player_name] or "") .. "]" ..
        "field_close_on_enter[secret_input;false]"

    if error_message then
        formspec = formspec .. "textarea[0.8,4.5;4.5,1.2;;;" .. core.formspec_escape(S("Error: ") .. error_message .. hint_text) .. "]"
    end

    formspec = formspec ..
        "button[0.8,3.25;2,0.8;secret_submit;" .. core.formspec_escape(S("Verify")) .. "]" ..
        "button[3,3.25;2.3,0.8;disconnect;" .. core.formspec_escape(S("Disconnect")) .. "]" ..
        "textarea[6.5,1.3;5,5;;;" .. core.formspec_escape(info_text) .. "]"

    core.show_formspec(player_name, formspec_name_verify, formspec)
end



local function cleanup_player_session(player_name)
    player_attempts[player_name] = nil
    player_verified[player_name] = nil
    player_last_input[player_name] = nil
end



local function kick_player_with_reason(player_name, reason)
    cleanup_player_session(player_name)
    core.kick_player(player_name, reason)
end



local function handle_setup_submit(player_name, secret)
    local valid, error_msg = is_valid_secret(secret)
    if not valid then
        core.chat_send_player(player_name, string.format(S("[Security] %s"), error_msg))
        show_setup_formspec(player_name)
        return
    end
    save_secret(player_name, secret)
    save_secret_hint(player_name, secret)
    player_verified[player_name] = true
    core.close_formspec(player_name, formspec_name_setup)
    core.chat_send_player(player_name, S("[Security] Secret word created successfully. Keep it safe!"))
end



local function handle_no_secret_choice(player_name)
    save_no_secret_choice(player_name)
    player_verified[player_name] = true
    core.close_formspec(player_name, formspec_name_setup)
    core.chat_send_player(player_name, S("[Security] You chose not to use a secret word."))
end



local function handle_verify_submit(player_name, secret)
    player_last_input[player_name] = secret
    if verify_secret(player_name, secret) then
        player_verified[player_name] = true
        core.close_formspec(player_name, formspec_name_verify)
        core.chat_send_player(player_name, S("[Security] Identity verified successfully. Welcome back!"))
    else
        player_attempts[player_name] = (player_attempts[player_name] or 0) + 1
        local attempts_left = max_attempts - player_attempts[player_name]
        if attempts_left <= 0 then
            kick_player_with_reason(player_name, S("Authentication failed: Too many incorrect attempts"))
        else
            local error_msg = string.format(S("Incorrect! %d attempt(s) remaining."), attempts_left)
            core.chat_send_player(player_name, "[Security] " .. error_msg)
            show_verify_formspec(player_name, error_msg)
        end
    end
end

local formspec_name_manage = "twofactor_authentication:manage"

local function show_manage_formspec(player_name)
    local hint = get_secret_hint(player_name)
    local hint_text = (hint and hint ~= "") and (S("Hint: ") .. hint) or S("No hint available.")
    local formspec = "formspec_version[4]" ..
        "size[12,7]" ..
        "allow_close[true]" ..
        "label[0.5,0.5;" .. core.formspec_escape(S("Account Security")) .. "]" ..
        "textarea[0.8,1.3;10,2;;;" ..
        core.formspec_escape(S("You already have a secret word.") .. "\n" .. hint_text) ..
        "]" ..
        "button[0.8,3.25;4.5,0.8;reset_confirm;" .. core.formspec_escape(S("Reset my secret word")) .. "]" ..
        "button[0.8,4.25;4.5,0.8;cancel;" .. core.formspec_escape(S("Cancel")) .. "]"
    core.show_formspec(player_name, formspec_name_manage, formspec)
end

core.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    player_attempts[player_name] = 0
    player_verified[player_name] = false
    player_last_input[player_name] = ""
    if wants_no_secret(player_name) then
        player_verified[player_name] = true
    elseif has_secret(player_name) then
        show_verify_formspec(player_name)
    else
        --show_setup_formspec(player_name)
    end
end)


core.register_on_player_receive_fields(function(player, formname, fields)
    if not player then
        return false
    end
    local player_name = player:get_player_name()

    if formname == formspec_name_setup then
        if fields.disconnect then
            kick_player_with_reason(player_name, S("Disconnected by user choice"))
            return true
        end
        if fields.no_secret then
            handle_no_secret_choice(player_name)
            return true
        end
        if fields.secret_submit or fields.key_enter_field == "secret_input" then
            handle_setup_submit(player_name, fields.secret_input or "")
        end
        return true
    end

    if formname == formspec_name_verify then
        if fields.quit then
            core.after(0, function()
                if core.get_player_by_name(player_name) then
                    show_verify_formspec(player_name)
                end
            end)
            return false
        end
        if fields.disconnect then
            kick_player_with_reason(player_name, S("Disconnected by user choice"))
            return true
        end
        if fields.secret_submit or fields.key_enter_field == "secret_input" then
            handle_verify_submit(player_name, fields.secret_input or "")
        end
        return true
    end

    if formname == formspec_name_manage then
        if fields.reset_confirm then
            storage:set_string(string.format("secret_%s", player_name), "")
            storage:set_string(string.format("hint_%s", player_name), "")
            core.close_formspec(player_name, formspec_name_manage)
            core.chat_send_player(player_name, S("[Security] Secret word reset. Create a new one:"))
            show_setup_formspec(player_name)
            return true
        end
        if fields.cancel or fields.quit then
            core.close_formspec(player_name, formspec_name_manage)
            return true
        end
        return true
    end

    return false
end)



core.register_on_leaveplayer(function(player)
    cleanup_player_session(player:get_player_name())
end)



core.register_chatcommand("reset_secret", {
    params = "",
    description = S("Reset your secret word"),
    func = function(name, param)
        if not player_verified[name] then
            return false, S("You must be verified to use this command")
        end
        storage:set_string(string.format("secret_%s", name), "")
        storage:set_string(string.format("hint_%s", name), "")
        return true, S("Secret word reset. You will be asked to create a new one on next login.")
    end,
})


core.register_craftitem("twofactor_authentication:settings", {
    description = S("Account Security"),
    inventory_image = "protection.png",

    on_drop = function(itemstack, dropper, pos)
        return itemstack
    end,

    on_use = function(itemstack, user, pointed_thing)
        if not user then return itemstack end
        local pname = user:get_player_name()

        if has_secret(pname) and not wants_no_secret(pname) then
            show_manage_formspec(pname)
        else
            show_setup_formspec(pname)
        end

        return itemstack
    end,
})
--[[
core.register_allow_player_inventory_action(function(player, action, inventory, inventory_info)
    if action == "move" then
        local from_stack = inventory:get_stack(inventory_info.from_list, inventory_info.from_index)
        local to_stack   = inventory:get_stack(inventory_info.to_list,   inventory_info.to_index)
        if from_stack:get_name() == "twofactor_authentication:settings" or to_stack:get_name() == "twofactor_authentication:settings" then
            return 0
        end
    elseif action == "take" then
        local stack = inventory:get_stack(inventory_info.listname, inventory_info.index)
        if stack:get_name() == "twofactor_authentication:settings" then
            return 0
        end
    elseif action == "put" then
        if inventory_info.stack:get_name() == "twofactor_authentication:settings" then
            return 0
        end
    end
end)


core.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    local inv = player:get_inventory()
    if not inv:contains_item("main", "twofactor_authentication:settings") then
        inv:set_stack("main", 5, ItemStack("twofactor_authentication:settings"))
    end
end)
]]
