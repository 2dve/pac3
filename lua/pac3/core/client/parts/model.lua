local pac = pac

local render_SetColorModulation = render.SetColorModulation
local render_SetBlend = render.SetBlend
local render_CullMode = render.CullMode
local MATERIAL_CULLMODE_CW = MATERIAL_CULLMODE_CW
local MATERIAL_CULLMODE_CCW = MATERIAL_CULLMODE_CCW
local render_SetMaterial = render.SetMaterial
local render_ModelMaterialOverride = render.MaterialOverride
local render_MaterialOverride = render.ModelMaterialOverride

local Vector = Vector
local EF_BONEMERGE = EF_BONEMERGE
local NULL = NULL
local Color = Color

local BUILDER, PART = pac.PartTemplate("base_drawable")

PART.FriendlyName = "model"
PART.ClassName = "model2"
PART.Category = "model"
PART.ManualDraw = true
PART.HandleModifiersManually = true
PART.Icon = 'icon16/shape_square.png'
PART.is_model_part = true
PART.ProperColorRange = true
PART.Group = 'model'

BUILDER:StartStorableVars()
	:SetPropertyGroup("generic")
		:GetSet("Model", "", {editor_panel = "model"})

	:SetPropertyGroup("orientation")
		:GetSet("Size", 1, {editor_sensitivity = 0.25})
		:GetSet("Scale", Vector(1,1,1))
		:GetSet("BoneMerge", false)

	:SetPropertyGroup("appearance")
		:GetSet("Color", Vector(1, 1, 1), {editor_panel = "color2"})
		:GetSet("NoLighting", false)
		:GetSet("NoCulling", false)
		:GetSet("Invert", false)
		:GetSet("Alpha", 1, {editor_sensitivity = 0.25, editor_clamp = {0, 1}})
		:GetSet("ModelModifiers", "", {editor_panel = "model_modifiers"})
		:GetSet("Material", "", {editor_panel = "material"})
		:GetSet("Materials", "", {editor_panel = "model_materials"})
		:GetSet("Skin", 0, {editor_onchange = function(self, num) return math.Round(math.max(tonumber(num), 0)) end})
		:GetSet("LevelOfDetail", 0, {editor_clamp = {-1, 8}, editor_round = true})
		:GetSetPart("EyeTarget")

:EndStorableVars()

PART.Entity = NULL

function PART:GetNiceName()
	local str = pac.PrettifyName(("/" .. self:GetModel()):match(".+/(.-)%."))

	return str and str:gsub("%d", "") or "error"
end

local temp = CreateMaterial(tostring({}), "VertexLitGeneric", {})

function PART:SetLevelOfDetail(val)
	self.LevelOfDetail = val
	local ent = self:GetEntity()
	if ent:IsValid() then
		ent:SetLOD(val)
	end
end

function PART:SetSkin(var)
	self.Skin = var

	if self.Entity:IsValid() then
		self.Entity:SetSkin(var)
	end
end

function PART:ModelModifiersToTable(str)
	if str == "" or (not str:find(";", nil, true) and not str:find("=", nil, true)) then return {} end

	local tbl = {}
	for _, data in ipairs(str:Split(";")) do
		local key, val = data:match("(.+)=(.+)")
		if key then
			key = key:Trim()
			val = tonumber(val:Trim())

			tbl[key] = val
		end
	end

	return tbl
end

function PART:ModelModifiersToString(tbl)
	local str = ""
	for k,v in pairs(tbl) do
		str = str .. k .. "=" .. v .. ";"
	end
	return str
end

function PART:SetModelModifiers(str)
	self.ModelModifiers = str

	if not self.Entity:IsValid() then return end

	local tbl = self:ModelModifiersToTable(str)

	if tbl.skin then
		self.Entity:SetSkin(tbl.skin)
		tbl.skin = nil
	end

	if not self.Entity:GetBodyGroups() then return end

	self.draw_bodygroups = {}

	for i, info in ipairs(self.Entity:GetBodyGroups()) do
		local val = tbl[info.name]
		if val then
			table.insert(self.draw_bodygroups, {info.id, val})
		end
	end
end

function PART:SetMaterial(str)
	self.Material = str

	if str == "" then
		if self.material_override_self then
			self.material_override_self[0] = nil
		end
	else
		self.material_override_self = self.material_override_self or {}

		if not pac.Handleurltex(self, str, function(mat)
			self.material_override_self = self.material_override_self or {}
			self.material_override_self[0] = mat
		end) then
			self.material_override_self[0] = pac.Material(str, self)
		end
	end

	if self.material_override_self and not next(self.material_override_self) then
		self.material_override_self = nil
	end
end

function PART:SetMaterials(str)
	self.Materials = str

	local materials = self:GetEntity():IsValid() and self:GetEntity():GetMaterials()

	if not materials then return end

	self.material_count = #materials

	self.material_override_self = self.material_override_self or {}

	local tbl = str:Split(";")

	for i = 1, #materials do
		local path = tbl[i]

		if path and path ~= "" then
			if not pac.Handleurltex(self, path, function(mat)
				self.material_override_self = self.material_override_self or {}
				self.material_override_self[i] = mat
			end) then
				self.material_override_self[i] = pac.Material(path, self)
			end
		else
			self.material_override_self[i] = nil
		end
	end

	if not next(self.material_override_self) then
		self.material_override_self = nil
	end
end

function PART:Reset()
	self:Initialize()
	for _, key in pairs(self:GetStorableVars()) do
		if PART[key] then
			self["Set" .. key](self, self["Get" .. key](self))
		end
	end
end

function PART:OnEvent(typ)
	if typ == "become_physics" then
		local ent = self:GetEntity()
		if ent:IsValid() then
			ent:PhysicsInit(SOLID_NONE)
			ent:SetMoveType(MOVETYPE_NONE)
			ent:SetNoDraw(true)
			ent.RenderOverride = nil

			self.skip_orient = false
		end
	end
end

function PART:Initialize()
	self.Entity = pac.CreateEntity(self:GetModel())
	self.Entity:SetNoDraw(true)
	self.Entity.PACPart = self
	self.material_count = 0
end

function PART:GetEntity()
	return self.Entity or NULL
end

function PART:OnShow()
	local owner = self:GetOwner()
	local ent = self:GetEntity()

	if ent:IsValid() and owner:IsValid() and owner ~= ent then
		ent:SetPos(owner:EyePos())
		self.BoneIndex = nil
	end
end

function PART:OnThink()
	self:CheckBoneMerge()
end

function PART:BindMaterials(ent)
	local materials = self.material_override_self or self.material_override
	local material_bound = false

	if self.material_override_self then
		if materials[0] then
			render_MaterialOverride(materials[0])
			material_bound = true
		end

		for i = 1, self.material_count do
			local mat = materials[i]

			if mat then
				render.MaterialOverrideByIndex(i-1, mat)
			else
				render.MaterialOverrideByIndex(i-1, nil)
			end
		end
	elseif self.material_override then
		if materials[0] and materials[0][1] then
			render_MaterialOverride(materials[0][1]:GetRawMaterial())
			material_bound = true
		end

		for i = 1, self.material_count do
			local stack = materials[i]
			if stack then
				local mat = stack[1]

				if mat then
					render.MaterialOverrideByIndex(i-1, mat:GetRawMaterial())
				else
					render.MaterialOverrideByIndex(i-1, nil)
				end
			end
		end
	end

	if self.BoneMerge and not material_bound then
		render_MaterialOverride()
	end

	return material_bound
end

function PART:PreEntityDraw(owner, ent, pos, ang)
	if not ent:IsPlayer() and pos and ang then
		if not self.skip_orient then
			ent:SetPos(pos)
			ent:SetAngles(ang)
		else
			self.cached_pos = pos
			self.cached_ang = ang
		end
	end

	if self.Alpha ~= 0 and self.Size ~= 0 then
		self:ModifiersPreEvent("OnDraw")

		local r, g, b = self.Color.r, self.Color.g, self.Color.b

		-- render.SetColorModulation and render.SetAlpha set the material $color and $alpha.
		render_SetColorModulation(r,g,b)
		render_SetBlend(self.Alpha)

		if self.NoLighting then
			render.SuppressEngineLighting(true)
		end
	end

	if self.draw_bodygroups then
		for _, v in ipairs(self.draw_bodygroups) do
			ent:SetBodygroup(v[1], v[2])
		end
	end

	if self.EyeTarget.cached_pos then
		if self.ClassName == "model2" then
			local attachment = ent:GetAttachment( ent:LookupAttachment( "eyes" ) )
			if attachment then
				ent:SetEyeTarget(WorldToLocal( self.EyeTarget.cached_pos, self.EyeTarget.cached_ang, attachment.Pos, attachment.Ang ))
			end
		else
			ent:SetEyeTarget(self.EyeTarget.cached_pos)
		end
	end
end

function PART:PostEntityDraw(owner, ent, pos, ang)
	if self.Alpha ~= 0 and self.Size ~= 0 then
		self:ModifiersPostEvent("OnDraw")

		if self.NoLighting then
			render.SuppressEngineLighting(false)
		end
	end
end

function PART:OnDraw(owner, pos, ang)
	local ent = self:GetEntity()

	if not ent:IsValid() then
		self:Reset()
		ent = self:GetEntity()
	end

	if self.loading then
		self:DrawLoadingText(ent, pos, ang)
		return
	end

	self:PreEntityDraw(owner, ent, pos, ang)
		self:DrawModel(ent, pos, ang)
	self:PostEntityDraw(owner, ent, pos, ang)

	pac.ResetBones(ent)
end

function PART:DrawModel(ent, pos, ang)
	if self.Alpha == 0 or self.Size == 0 then return end

	if self.NoCulling or self.Invert then
		render_CullMode(MATERIAL_CULLMODE_CW)
	end

	local material_bound = false

	material_bound = self:BindMaterials(ent) or material_bound

	ent.pac_drawing_model = true
	ent:DrawModel()
	ent.pac_drawing_model = false

	if pac.projected_texture_enabled and not pac.flashlight_disabled then
		render.PushFlashlightMode(true)

		material_bound = self:BindMaterials(ent) or material_bound
		ent.pac_drawing_model = true
		ent:DrawModel()
		ent.pac_drawing_model = false

		render.PopFlashlightMode()
	end

	if self.NoCulling then
		render_CullMode(MATERIAL_CULLMODE_CCW)
		material_bound = self:BindMaterials(ent) or material_bound
		ent:DrawModel()
	elseif self.Invert then
		render_CullMode(MATERIAL_CULLMODE_CCW)
	end

	-- need to unbind mateiral
	if material_bound then
	    render_MaterialOverride()
	end
end

function PART:DrawLoadingText(ent, pos, ang)
	cam.Start2D()
	cam.IgnoreZ(true)
		local pos2d = pos:ToScreen()

		surface.SetFont("DermaDefault")

		if self.errored then
			surface.SetTextColor(255, 0, 0, 255)
			local str = self.loading:match("^(.-):\n") or self.loading:match("^(.-)\n") or self.loading:sub(1, 100)
			local w, h = surface.GetTextSize(str)
			surface.SetTextPos(pos2d.x - w / 2, pos2d.y - h / 2)
			surface.DrawText(str)
		else
			surface.SetTextColor(255, 255, 255, 255)
			local str = self.loading .. string.rep(".", pac.RealTime * 3 % 3)
			local w, h = surface.GetTextSize(self.loading .. "...")

			surface.SetTextPos(pos2d.x - w / 2, pos2d.y - h / 2)
			surface.DrawText(str)
		end
	cam.IgnoreZ(false)
	cam.End2D()
end

local ALLOW_TO_MDL = CreateConVar('pac_allow_mdl', '1', CLIENT and {FCVAR_REPLICATED} or {FCVAR_ARCHIVE, FCVAR_REPLICATED}, 'Allow to use custom MDLs')

function PART:RefreshModel()

	self.Entity.pac_bones = nil
	if self.Entity.pac_holdtypes then
		self.Entity.pac_holdtypes = {}
	end

	self:SetModelModifiers(self:GetModelModifiers())
	self:SetMaterials(self:GetMaterials())
	self:SetSize(self:GetSize())
	self:SetScale(self:GetScale())
end

function PART:RealSetModel(path)
	self.Entity:SetModel(path)
	self:RefreshModel()
end

function PART:SetModel(path)
	self.Model = path
	self.Entity = self:GetEntity()

	if path:find("^.-://") then
		local status, reason = hook.Run('PAC3AllowMDLDownload', self:GetPlayerOwner(), self, path)

		if ALLOW_TO_MDL:GetBool() and status ~= false then
			self.loading = "downloading mdl zip"
			pac.DownloadMDL(path, function(mdl_path)
				self.loading = nil
				self.errored = nil

				local ent = self:GetEntity()

				if pacx and pacx.SetModel and self:GetPlayerOwner() == pac.LocalPlayer then
					pacx.SetModel(ent, path, self:GetPlayerOwner())
				end

				self:RealSetModel(mdl_path)

			end, function(err)

				if pace and pace.current_part == self and not IsValid(pace.BusyWithProperties) then
					pace.MessagePrompt(err, "HTTP Request Failed for " .. path, "OK")
				else
					pac.Message(Color(0, 255, 0), "[model] ", Color(255, 255, 255), "HTTP Request Failed for " .. path .. " - " .. err)
				end

				self.loading = err
				self.errored = true
				self:RealSetModel("models/error.mdl")
			end, self:GetPlayerOwner())
		else
			self.loading = reason or "mdl is not allowed"
			self:RealSetModel("models/error.mdl")
			pac.Message(self, ' mdl files are not allowed')
		end
	else
		local ent = self:GetEntity()

		if pacx and pacx.SetModel and self:GetPlayerOwner() == pac.LocalPlayer then
			pacx.SetModel(ent, path, self:GetPlayerOwner())
		end

		self:RealSetModel(path)
	end
end

local NORMAL = Vector(1,1,1)

function PART:CheckScale()
	-- RenderMultiply doesn't work with this..
	if self.BoneMerge and self.Entity:IsValid() and self.Entity:GetBoneCount() and self.Entity:GetBoneCount() > 1 then
		if self.Scale * self.Size ~= NORMAL then
			if not self.requires_bone_model_scale then
				self.requires_bone_model_scale = true
			end
			return true
		end

		self.requires_bone_model_scale = false
	end
end

function PART:SetAlternativeScaling(b)
	self.AlternativeScaling = b
	self:SetScale(self.Scale)
end

function PART:SetScale(var)
	var = var or Vector(1,1,1)

	self.Scale = var

	if not self:CheckScale() then
		self:ApplyMatrix()
	end
end

local vec_one = Vector(1,1,1)

function PART:ApplyMatrix()
	local ent = self:GetEntity()
	if not ent:IsValid() then return end

	local mat = Matrix()

	if self.ClassName ~= "model2" then
		mat:Translate(self.Position + self.PositionOffset)
		mat:Rotate(self.Angles + self.AngleOffset)
	end

	if ent:IsPlayer() or ent:IsNPC() then
		if pacx and pacx.SetEntitySizeMultiplier then
			local other = {
				StandingHullHeight = self.StandingHullHeight,
				CrouchingHullHeight = self.CrouchingHullHeight,
				HullWidth = self.HullWidth,
			}
			if self:GetPlayerOwner() == pac.LocalPlayer then
				pacx.SetEntitySizeOnServer(ent, self.Size, other)
			end
			pacx.SetEntitySizeMultiplier(ent, self.Size, other)
		end

		if self.Size == 1 and self.Scale == vec_one then
			if ent.pac_enable_ik then
				ent:SetModelScale(1, 0)
				ent:SetIK(true)
			else
				ent:SetModelScale(1.000001, 0)
				ent:SetIK(false)
			end
		end

		mat:Scale(self.Scale)
	else
		mat:Scale(self.Scale * self.Size)
	end

	if mat:IsIdentity() then
		ent:DisableMatrix("RenderMultiply")
	else
		ent:EnableMatrix("RenderMultiply", mat)
	end
end

function PART:SetSize(var)
	var = var or 1

	self.Size = var

	if not self:CheckScale() then
		self:ApplyMatrix()
	end
end

function PART:CheckBoneMerge()
	local ent = self.Entity

	if self.skip_orient then return end

	if ent:IsValid() and not ent:IsPlayer() and ent:GetModel() then
		if self.BoneMerge then
			--[[if not self.ragdoll then
				self.Entity = ClientsideRagdoll(ent:GetModel())
				self.requires_bone_model_scale = true
				ent = self.Entity
				self.ragdoll = true
			end]]

			local owner = self:GetOwner()

			if ent:GetParent() ~= owner then
				ent:SetParent(owner)

				if not ent:IsEffectActive(EF_BONEMERGE) then
					ent:AddEffects(EF_BONEMERGE)
					owner.pac_bonemerged = owner.pac_bonemerged or {}
					table.insert(owner.pac_bonemerged, ent)
					ent.RenderOverride = function()
						ent.pac_drawing_model = true
						ent:DrawModel()
						ent.pac_drawing_model = false
					end
				end
			end
		else
			--[[if self.ragdoll then
				self.Entity:Remove()
				ent = self:GetEntity()
				self.requires_bone_model_scale = true
				self.ragdoll = false
			end]]

			if ent:GetParent():IsValid() then
				local owner = ent:GetParent()
				ent:SetParent(NULL)

				if ent:IsEffectActive(EF_BONEMERGE) then
					ent:RemoveEffects(EF_BONEMERGE)
					ent.RenderOverride = nil

					if owner:IsValid() then
						owner.pac_bonemerged = owner.pac_bonemerged or {}
						for i, v in ipairs(owner.pac_bonemerged) do
							if v == ent then
								table.remove(owner.pac_bonemerged, i)
								break
							end
						end
					end
				end

				self.requires_bone_model_scale = false
			end
		end
	end
end

function PART:OnBuildBonePositions()
	if self.AlternativeScaling then return end

	local ent = self:GetEntity()
	local owner = self:GetOwner()

	if not ent:IsValid() or not owner:IsValid() or not ent:GetBoneCount() or ent:GetBoneCount() < 1 then return end

	if self.requires_bone_model_scale then
		local scale = self.Scale * self.Size

		for i = 0, ent:GetBoneCount() - 1 do
			if i == 0 then
				ent:ManipulateBoneScale(i, ent:GetManipulateBoneScale(i) * Vector(scale.x ^ 0.25, scale.y ^ 0.25, scale.z ^ 0.25))
			else
				ent:ManipulateBonePosition(i, ent:GetManipulateBonePosition(i) + Vector((scale.x-1) ^ 4, 0, 0))
				ent:ManipulateBoneScale(i, ent:GetManipulateBoneScale(i) * scale)
			end
		end
	end
end

BUILDER:Register()

do
	local BUILDER, PART = pac.PartTemplate("model2")

	PART.FriendlyName = "entity"
	PART.ClassName = "entity2"
	PART.Category = "entity"
	PART.ManualDraw = true
	PART.HandleModifiersManually = true
	PART.Icon = 'icon16/brick.png'
	PART.Group = "entity"
	PART.is_model_part = false

	BUILDER:StartStorableVars()
		:SetPropertyGroup("appearance")
			:GetSet("NoDraw", false)
			:GetSet("DrawShadow", true)
			:GetSet("InverseKinematics", false)

		:SetPropertyGroup("hull")
			:GetSet("StandingHullHeight", 72, {editor_panel = "hull"})
			:GetSet("CrouchingHullHeight", 36, {editor_panel = "hull", crouch = true})
			:GetSet("HullWidth", 32, {editor_panel = "hull"})
	:EndStorableVars()

	BUILDER:RemoveProperty("BoneMerge")
	BUILDER:RemoveProperty("Bone")
	BUILDER:RemoveProperty("EyeAngles")
	BUILDER:RemoveProperty("AimPartName")

	function PART:SetStandingHullHeight(val)
		self.StandingHullHeight = val
		self:ApplyMatrix()
	end
	function PART:SetCrouchingHullHeight(val)
		self.CrouchingHullHeight = val
		self:ApplyMatrix()
	end
	function PART:SetHullWidth(val)
		self.HullWidth = val
		self:ApplyMatrix()
	end

	function PART:GetNiceName()
		local str = pac.PrettifyName(("/" .. self:GetModel()):match(".+/(.-)%.")) or self:GetModel()

		local class_name = "NULL"
		local ent = self:GetEntity()

		if ent:IsValid() then
			class_name = ent:GetClass()
		end

		return (str and str:gsub("%d", "") or "error") .. " " .. class_name .. " model"
	end

	function PART:SetPosition(pos)
		self.Position = pos
		self:ApplyMatrix()
	end

	function PART:SetAngles(ang)
		self.Angles = ang
		self:ApplyMatrix()
	end

	function PART:SetPositionOffset(pos)
		self.PositionOffset = pos
		self:ApplyMatrix()
	end

	function PART:SetAngleOffset(ang)
		self.AngleOffset = ang
		self:ApplyMatrix()
	end

	function PART:GetBonePosition()
		local ent = self:GetOwner()
		local ang = ent:GetAngles()
		if ent:IsPlayer() then
			ang.p = 0
		end
		return ent:GetPos(), ang
	end

	function PART:Initialize()
		self.material_count = 0
	end

	function PART:OnDraw(ent, pos, ang)
		self:PreEntityDraw(ent, ent, pos, ang)
			self:DrawModel(ent, pos, ang)
		self:PostEntityDraw(ent, ent, pos, ang)
	end

	function PART:GetEntity()
		local ent = self:GetOwner()
		self.Entity = ent
		return ent
	end

	local temp_mat = Material( "models/error/new light1" )

	function PART:OnShow()
		local ent = self:GetEntity()

		if self.Model == "" then
			self.Model = pacx and pacx.GetModel(ent) or ent:GetModel() or ""
		end

		if ent:IsValid() then
			function ent.RenderOverride()
				-- if the draw call is not from pac don't bother
				if not ent.pac_drawing_model then
					return
				end

				if self:IsValid() and self:GetOwner():IsValid() then
					if ent.pac_bonemerged then
						for _, e in ipairs(ent.pac_bonemerged) do
							if e.pac_drawing_model then return end
						end
					end

					-- so eyes work
					if self.NoDraw then
						render.SetBlend(0)
						render.ModelMaterialOverride(temp_mat)
						ent:DrawModel()
						render.SetBlend(1)
						render.ModelMaterialOverride()
						return
					end

					self:Draw(ent:GetPos(), ent:GetAngles(), self.Translucent and "translucent" or "opaque")
				else
					ent.RenderOverride = nil
				end
			end
			self:SetDrawShadow(self:GetDrawShadow())
			self:ApplyMatrix()
		end
	end

	function PART:OnHide()
		local ent = self:GetOwner()

		if ent:IsValid() then
			ent.RenderOverride = nil
			ent:DisableMatrix("RenderMultiply")
		end
	end

	function PART:RealSetModel(path)
		local ent = self:GetEntity()
		if not ent:IsValid() then return end

		ent:SetModel(path)

		self:RefreshModel()
	end

	function PART:OnRemove()
		local ent = self:GetEntity()
		if not ent:IsValid() then return end

		if pacx and pacx.SetModel and self:GetPlayerOwner() == pac.LocalPlayer then
			pacx.SetModel(ent, nil, self:GetPlayerOwner())
		end

		if ent:IsPlayer() or ent:IsNPC() then
			if pacx and pacx.SetEntitySizeMultiplier then
				if self:GetPlayerOwner() == pac.LocalPlayer then
					pacx.SetEntitySizeOnServer(ent)
				end
				pacx.SetEntitySizeMultiplier(ent)
			end

		end

		ent:DisableMatrix("RenderMultiply")
	end

	function PART:SetInverseKinematics(b)
		self.InverseKinematics = b

		local ent = self:GetOwner()

		if ent:IsValid() then
			ent.pac_enable_ik = b
			self:ApplyMatrix()
		end
	end

	function PART:OnThink()
		self:CheckBoneMerge()

		local ent = self:GetEntity()

		if ent:IsValid() then
			local old = pacx and pacx.GetModel(ent) or ent:GetModel()
			if self.last_model ~= old then
				self:RefreshModel()
				self.last_model = old
			end
		end
	end

	BUILDER:Register()
end

do
	local BUILDER, PART = pac.PartTemplate("model2")

	PART.ClassName = "weapon"
	PART.FriendlyName = "weapon"
	PART.Category = "entity"
	PART.ManualDraw = true
	PART.HandleModifiersManually = true
	PART.Icon = 'icon16/brick.png'
	PART.Group = "entity"
	PART.is_model_part = false

	BUILDER:StartStorableVars()
		:SetPropertyGroup("generic")
			:GetSet("OverridePosition", false)
			:GetSet("Class", "all", {enums = function()
				local out = {
					["physgun"] = "weapon_physgun",
					["357"] = "weapon_357",
					["alyxgun"] = "weapon_alyxgun",
					["annabelle"] = "weapon_annabelle",
					["ar2"] = "weapon_ar2",
					["brickbat"] = "weapon_brickbat",
					["bugbait"] = "weapon_bugbait",
					["crossbow"] = "weapon_crossbow",
					["crowbar"] = "weapon_crowbar",
					["frag"] = "weapon_frag",
					["physcannon"] = "weapon_physcannon",
					["pistol"] = "weapon_pistol",
					["rpg"] = "weapon_rpg",
					["shotgun"] = "weapon_shotgun",
					["smg1"] = "weapon_smg1",
					["striderbuster"] = "weapon_striderbuster",
					["stunstick"] = "weapon_stunstick",
				}
				for _, tbl in pairs(weapons.GetList()) do
					if not tbl.ClassName:StartWith("ai_") then
						local friendly = tbl.ClassName:match("weapon_(.+)") or tbl.ClassName
						out[friendly] = tbl.ClassName
					end
				end
				return out
			end})
		:SetPropertyGroup("appearance")
			:GetSet("NoDraw", false)
			:GetSet("DrawShadow", true)
		:EndStorableVars()

	BUILDER:RemoveProperty("Model")

	function PART:SetDrawShadow(b)
		self.DrawShadow = b

		local ent = self:GetEntity()
		if not ent:IsValid() then return end

		ent:DrawShadow(b)
		ent:MarkShadowAsDirty()
	end

	function PART:GetNiceName()
		if self.Class ~= "all" then
			return self.Class
		end
		return self.ClassName
	end

	function PART:Initialize()
		self.material_count = 0
	end
	function PART:OnDraw(ent, pos, ang)
		local ent = self:GetEntity()
		if not ent:IsValid() then return end

		local old
		if self.OverridePosition then
			old = ent:GetParent()
			ent:SetParent(NULL)
			ent:SetRenderOrigin(pos)
			ent:SetRenderAngles(ang)
			ent:SetupBones()
		end
		ent.pac_render = true

		self:PreEntityDraw(ent, ent, pos, ang)
			self:DrawModel(ent, pos, ang)
		self:PostEntityDraw(ent, ent, pos, ang)
		pac.ResetBones(ent)

		if self.OverridePosition then
			ent:MarkShadowAsDirty()
			--ent:SetParent(old)
		end
		ent.pac_render = nil
	end

	PART.AlwaysThink = true

	function PART:OnThink()
		local ent = self:GetOwner(true)
		if ent:IsValid() and ent.GetActiveWeapon then
			local wep = ent:GetActiveWeapon()
			if wep:IsValid() then
				if wep ~= self.Entity then
					if self.Class == "all" or (self.Class:lower() == wep:GetClass():lower()) then
						self:OnHide()
						self.Entity = wep
						self:SetEventHide(false)
						wep.RenderOverride = function()
							if wep.pac_render then
								if not self.NoDraw then
									if self.DrawShadow then
										wep:CreateShadow()
									end
									wep:DrawModel()
								end
							end
						end
						wep.pac_weapon_part = self
						self:SetDrawShadow(self:GetDrawShadow())
					else
						self:SetEventHide(true)
						self:OnHide()
					end
				end
			end
		end
	end

	function PART:OnHide()
		local ent = self:GetOwner(true)

		if ent:IsValid() and ent.GetActiveWeapon then
			for k,v in pairs(ent:GetWeapons()) do
				if v.pac_weapon_part == self then
					v.RenderOverride = nil
					v:SetParent(ent)
				end
			end
			self.Entity = NULL
		end
	end

	BUILDER:Register()
end
