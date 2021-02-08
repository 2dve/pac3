local pac = pac

local render_SetColorModulation = render.SetColorModulation
local render_SetBlend = render.SetBlend
local render_ModelMaterialOverride = render.ModelMaterialOverride
local render_MaterialOverride = render.MaterialOverride
local SysTime = SysTime
local util_TimerCycle = util.TimerCycle
local FrameTime = FrameTime
local NULL = NULL
local pairs = pairs
local force_rendering = false
local forced_rendering = false

local cvar_projected_texture = CreateClientConVar("pac_render_projected_texture", "0")

local render_time = math.huge
CreateClientConVar("pac_max_render_time", 0)
local max_render_time = 0

local TIME = math.huge

local entMeta = FindMetaTable('Entity')
local plyMeta = FindMetaTable('Player')
local IsValid = entMeta.IsValid
local Alive = plyMeta.Alive

local function IsActuallyValid(ent)
	return IsEntity(ent) and pcall(ent.GetPos, ent)
end

local function IsActuallyPlayer(ent)
	return IsEntity(ent) and pcall(ent.UniqueID, ent)
end

local function IsActuallyRemoved(ent, cb)
	timer.Simple(0, function()
		if not ent:IsValid() then
			cb()
		end
	end)
end

--[[
	This state can happen when the Player is joined but not yet fully connected.
	At this point the SteamID is not yet set and the UniqueID call fails with a lua error.
]]
local function IsActuallyPlayer(ent)
	return IsEntity(ent) and pcall(ent.UniqueID, ent)
end

function pac.ForceRendering(b)
	force_rendering = b
	if b then
		forced_rendering = b
	end
end

local ent_parts = {}
local all_parts = {}
local uid_parts = {}

local function parts_from_uid(owner_id)
	return uid_parts[owner_id] or {}
end

local function parts_from_ent(ent)
	local owner_id = IsValid(ent) and ent:IsPlayer() and ent:UniqueID() or ent:EntIndex()
	return uid_parts[owner_id] or {}
end

do
	function pac.UpdateEntityParts(ent, update_type)
		pac.RealTime = RealTime()
		pac.FrameNumber = FrameNumber()
		ent.pac_model = ent:GetModel()

		local parts = ent_parts[ent]
		if not parts then return end

		if update_type ~= "update" then
			pac.ResetBones(ent)
		end

		for key, root in pairs(parts) do
			if update_type == "update" then
				for _, part in ipairs(root:GetChildrenList()) do
					part:CThink()
				end
			else
				for _, part in ipairs(root:GetChildrenList()) do
					if not part.OnBuildBonePositions then continue end

					if part.OwnerName ~= "hands" and update_type == "hands" then continue end
					if part.OwnerName ~= "viewmodel" and update_type == "viewmodel" then continue end

					if part:IsHidden() or part:GetEventHide() then continue end

					part:OnBuildBonePositions()
				end

				for _, part in ipairs(root:GetChildrenList()) do
					if not part.Draw then continue end

					if part.OwnerName ~= "hands" and update_type == "hands" then continue end
					if part.OwnerName ~= "viewmodel" and update_type == "viewmodel" then continue end

					part:Draw(nil, nil, update_type)
				end
			end
		end

		render_SetColorModulation(1, 1, 1)
		render_SetBlend(1)

		render_MaterialOverride()
		render_ModelMaterialOverride()
	end
end

function pac.HideEntityParts(ent)
	if ent_parts[ent] and ent.pac_drawing then
		for _, part in pairs(ent_parts[ent]) do
			part:SetDrawHidden(true)
		end

		pac.ResetBones(ent)
		ent.pac_drawing = false
	end
end

function pac.ShowEntityParts(ent)
	if ent_parts[ent] and (not ent.pac_drawing) and (not ent.pac_shouldnotdraw) and (not ent.pac_ignored) then
		for _, part in pairs(ent_parts[ent]) do
			part:SetDrawHidden(false)
		end

		pac.ResetBones(ent)
		ent.pac_drawing = true
	end
end

function pac.EnableDrawnEntities(bool)
	for ent in next, pac.drawn_entities do
		if ent:IsValid() then
			if bool then
				pac.ShowEntityParts(ent)
			else
				pac.HideEntityParts(ent)
			end
		else
			pac.drawn_entities[ent] = nil
		end
	end
end

function pac.HookEntityRender(part)
	local hm = part
	local part = part:GetRootPart()
	local ent = part:GetOwner()

	if not ent:IsValid() or part.ClassName ~= "group" then
		print("uh oh!!!", part, hm, owner)
		return
	end

	local parts = ent_parts[ent]
	if not parts then
		parts = {}
		ent_parts[ent] = parts
	end

	if parts[part] then
		return
	end

	pac.dprint("hooking render on %s to draw part %s", tostring(ent), tostring(part))

	pac.drawn_entities[ent] = true

	parts[part] = part

	ent.pac_has_parts = true

	pac.ShowEntityParts(ent)
end

function pac.UnhookEntityRender(part)
	local hm = part
	part = part:GetRootPart()
	local ent = part:GetOwner()

	if not ent:IsValid() or part.ClassName ~= "group" then
		print("uh oh!!!", part, hm, owner)
		return
	end

	if part and ent_parts[ent] then
		ent_parts[ent][part] = nil
	end

	if (ent_parts[ent] and not next(ent_parts[ent])) or not part then
		ent_parts[ent] = nil
		ent.pac_has_parts = nil
		pac.drawn_entities[ent] = nil
	end

	pac.HideEntityParts(ent)
end

pac.AddHook("Think", "events", function()
	for _, ply in ipairs(player.GetAll()) do
		if not ent_parts[ply] then continue end

		if Alive(ply) then
			if ply.pac_revert_ragdoll then
				ply.pac_revert_ragdoll()
				ply.pac_revert_ragdoll = nil
			end
			continue
		end

		local rag = ply:GetRagdollEntity()
		if not IsValid(rag) then continue end

		-- so it only runs once
		if ply.pac_ragdoll == rag then continue end
		ply.pac_ragdoll = rag
		rag.pac_player = ply

		rag = hook.Run("PACChooseDeathRagdoll", ply, rag) or rag

		if ply.pac_death_physics_parts then
			if ply.pac_physics_died then return end

			pac.CallPartEvent("physics_ragdoll_death", rag, ply)

			for _, part in pairs(parts_from_uid(ply:UniqueID())) do
				if part.is_model_part then
					local ent = part:GetEntity()
					if ent:IsValid() then
						rag:SetNoDraw(true)

						part.skip_orient = true

						ent:SetParent(NULL)
						ent:SetNoDraw(true)
						ent:PhysicsInitBox(Vector(1,1,1) * -5, Vector(1,1,1) * 5)
						ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

						local phys = ent:GetPhysicsObject()
						phys:AddAngleVelocity(VectorRand() * 1000)
						phys:AddVelocity(ply:GetVelocity()  + VectorRand() * 30)
						phys:Wake()

						function ent.RenderOverride()
							if part:IsValid() then
								if not part.HideEntity then
									part:PreEntityDraw(ent, ent, ent:GetPos(), ent:GetAngles())
									ent:DrawModel()
									part:PostEntityDraw(ent, ent, ent:GetPos(), ent:GetAngles())
								end
							else
								ent.RenderOverride = nil
							end
						end
					end
				end
			end
			ply.pac_physics_died = true
		elseif ply.pac_death_ragdollize or ply.pac_death_ragdollize == nil then

			pac.HideEntityParts(ply)

			for _, part in pairs(ent_parts[ply]) do
				part:SetOwner(rag)
			end

			pac.ShowEntityParts(rag)

			ply.pac_revert_ragdoll = function()
				ply.pac_ragdoll = nil

				if not ent_parts[ply] then return end

				pac.HideEntityParts(rag)

				for _, part in pairs(ent_parts[ply]) do
					part:SetOwner(ply)
				end

				pac.ShowEntityParts(ply)
			end
		end
	end

	do
		local mode = cvar_projected_texture:GetInt()

		if mode <= 0 then
			pac.projected_texture_enabled = false
		elseif mode == 1 then
			pac.projected_texture_enabled = true
		elseif mode >= 2 then
			pac.projected_texture_enabled = pac.LocalPlayer:FlashlightIsOn()
		end
	end

	for ent in next, pac.drawn_entities do
		if IsValid(ent) then
			if ent.pac_drawing and ent:IsPlayer() then

				ent.pac_traceres = util.QuickTrace(ent:EyePos(), ent:GetAimVector() * 32000, {ent, ent:GetVehicle(), ent:GetOwner()})
				ent.pac_hitpos = ent.pac_traceres.HitPos

			end
		else
			pac.drawn_entities[ent] = nil
		end
	end

	if pac.next_frame_funcs then
		for k, fcall in pairs(pac.next_frame_funcs) do
			fcall()
		end

		-- table.Empty is also based on undefined behavior
		-- god damnit
		for i, key in ipairs(table.GetKeys(pac.next_frame_funcs)) do
			pac.next_frame_funcs[key] = nil
		end
	end

	if pac.next_frame_funcs_simple and #pac.next_frame_funcs_simple ~= 0 then
		for i, fcall in ipairs(pac.next_frame_funcs_simple) do
			fcall()
		end

		for i = #pac.next_frame_funcs_simple, 1, -1 do
			pac.next_frame_funcs_simple[i] = nil
		end
	end
end)

pac.AddHook("EntityRemoved", "change_owner", function(ent)
	if IsActuallyValid(ent) then
		if IsActuallyPlayer(ent) then
			local parts = parts_from_ent(ent)
			if next(parts) ~= nil then
				IsActuallyRemoved(ent, function()
					for _, part in pairs(parts) do
						if part.dupe_remove then
							part:Remove()
						end
					end
				end)
			end
		else
			local owner = ent:GetOwner()
			if IsActuallyPlayer(owner) then
				local parts = parts_from_ent(owner)
				if next(parts) ~= nil then
					IsActuallyRemoved(ent, function()
						for _, part in pairs(parts) do
							if not part:HasParent() then
								part:CheckOwner(ent, true)
							end
						end
					end)
				end
			end
		end
	end
end)

pac.AddHook("OnEntityCreated", "change_owner", function(ent)
	if not IsActuallyValid(ent) then return end

	local owner = ent:GetOwner()

	if IsActuallyValid(owner) and (not owner:IsPlayer() or IsActuallyPlayer(owner)) then
		for _, part in pairs(parts_from_ent(owner)) do
			if not part:HasParent() then
				part:CheckOwner(ent, false)
			end
		end
	end
end)

function pac.RemovePartsFromUniqueID(uid)
	for _, part in pairs(parts_from_uid(uid)) do
		if not part:HasParent() then
			part:Remove()
		end
	end
end

function pac.UpdatePartsWithMetatable(META)
	-- update part functions only
	-- updating variables might mess things up
	for _, part in pairs(all_parts) do
		if part.ClassName == META.ClassName or META.ClassName == "base" then
			for k, v in pairs(META) do
				if type(v) == "function" then
					part[k] = v
				end
			end
		end
	end
end

function pac.GetPropertyFromName(func, name, ent_owner)
	for _, part in pairs(parts_from_ent(ent_owner)) do
		if part[func] and name == part.Name then
			return part[func](part)
		end
	end
end

function pac.RemoveUniqueIDPart(owner_uid, uid)
	if not uid_parts[owner_uid] then return end
	uid_parts[owner_uid][uid] = nil
end

function pac.SetUniqueIDPart(owner_uid, uid, part)
	uid_parts[owner_uid] = uid_parts[owner_uid] or {}
	uid_parts[owner_uid][uid] = part

	pac.NotifyPartCreated(part)
end

function pac.AddPart(part)
	all_parts[part.Id] = part
end

function pac.RemovePart(part)
	all_parts[part.Id] = nil
end

function pac.GetLocalParts()
	return uid_parts[pac.LocalPlayer:UniqueID()] or {}
end

function pac.GetPartFromUniqueID(owner_id, id)
	return uid_parts[owner_id] and uid_parts[owner_id][id] or NULL
end

function pac.FindPartByName(owner_id, str)
	if uid_parts[owner_id] then
		if uid_parts[owner_id][str] then
			return uid_parts[owner_id][str]
		end

		for _, part in pairs(uid_parts[owner_id]) do
			if part:GetName() == str then
				return part
			end
		end

		for _, part in pairs(uid_parts[owner_id]) do
			if pac.StringFind(part:GetName(), str) then
				return part
			end
		end

		for _, part in pairs(uid_parts[owner_id]) do
			if pac.StringFind(part:GetName(), str, true) then
				return part
			end
		end
	end

	return NULL
end

function pac.GetLocalPart(id)
	local owner_id = pac.LocalPlayer:UniqueID()
	return uid_parts[owner_id] and uid_parts[owner_id][id] or NULL
end

function pac.RemoveAllParts(owned_only, server)
	if server and pace then
		pace.RemovePartOnServer("__ALL__")
	end

	for _, part in pairs(owned_only and pac.GetLocalParts() or all_parts) do
		if part:IsValid() then
			local status, err = pcall(part.Remove, part)
			if not status then pac.Message('Failed to remove part: ' .. err .. '!') end
		end
	end

	if not owned_only then
		all_parts = {}
		uid_parts = {}
	end
end

function pac.UpdateMaterialParts(how, uid, self, val)
	pac.RunNextFrame("material " .. how .. " " .. self.Id, function()
		for _, part in pairs(parts_from_uid(uid)) do
			if how == "update" or how == "remove" then
				if part.Materialm == val and self ~= part then
					if how == "update" then
						part.force_translucent = self.Translucent
					else
						part.force_translucent = nil
						part.Materialm = nil
					end
				end
			elseif how == "show" then
				if part.Material and part.Material ~= "" and part.Material == val then
					part:SetMaterial(val)
				end
			end
		end
	end)
end

function pac.NotifyPartCreated(part)
	local owner_id = part:GetPlayerOwnerId()
	if not uid_parts[owner_id] then return end

	for _, p in pairs(uid_parts[owner_id]) do
		p:OnOtherPartCreated(part)
	end
end

function pac.CallPartEvent(event, ...)
	for _, part in pairs(all_parts) do
		local ret = part:OnEvent(event, ...)
		if ret ~= nil then
			return ret
		end
	end
end


do -- drawing
	local pac = pac

	local render_SetColorModulation = render.SetColorModulation
	local render_SetBlend = render.SetBlend
	local render_ModelMaterialOverride = render.ModelMaterialOverride
	local render_CullMode = render.CullMode
	local render_SuppressEngineLighting = render.SuppressEngineLighting
	local FrameNumber = FrameNumber
	local RealTime = RealTime
	local GetConVar = GetConVar
	local NULL = NULL
	local EF_BONEMERGE = EF_BONEMERGE
	local RENDERMODE_TRANSALPHA = RENDERMODE_TRANSALPHA
	local pairs = pairs
	local util_PixelVisible = util.PixelVisible

	local cvar_distance = CreateClientConVar("pac_draw_distance", "500")
	local cvar_fovoverride = CreateClientConVar("pac_override_fov", "0")

	local max_render_time_cvar = CreateClientConVar("pac_max_render_time", 0)

	local entMeta = FindMetaTable('Entity')
	local plyMeta = FindMetaTable('Player')
	local IsValid = entMeta.IsValid
	local Alive = plyMeta.Alive

	pac.Errors = {}
	pac.firstperson_parts = pac.firstperson_parts or {}
	pac.EyePos = vector_origin
	pac.drawn_entities = pac.drawn_entities or {}
	pac.LocalPlayer = LocalPlayer()
	pac.RealTime = 0
	pac.FrameNumber = 0

	local function update(func)
		for ent in next, pac.drawn_entities do
			if ent:IsValid() and ent_parts[ent] then
				pac.UpdateEntityParts(ent, func)
			end
		end
	end

	pac.AddHook("Think", "update_parts", function()
		update("update")
	end)

	pac.AddHook("PostDrawOpaqueRenderables", "draw_opaque", function(bDrawingDepth, bDrawingSkybox)
		update("opaque")
	end)

	pac.AddHook("PostDrawTranslucentRenderables", "draw_translucent", function(bDrawingDepth, bDrawingSkybox)
		update("translucent")
	end)

	pac.AddHook("PostDrawViewModel", "draw_firstperson", function(viewmodelIn, playerIn, weaponIn)
		update("viewmodel")
	end)

	pac.LocalHands = NULL

	pac.AddHook("PostDrawPlayerHands", "draw_firstperson_hands", function(handsIn, viewmodelIn, playerIn, weaponIn)
		pac.LocalHands = handsIn

		update("hands")
	end)
end
