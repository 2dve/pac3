local pac = pac
local pairs = pairs
local ipairs = ipairs
local table = table
local Vector = Vector
local Angle = Angle
local Color = Color
local NULL = NULL
local SysTime = SysTime

local LocalToWorld = LocalToWorld

local BUILDER, PART = pac.PartTemplate("base_movable")

PART.ClassName = "base_drawable"

function PART:__tostring()
	return string.format("%s[%s][%s][%i]", self.Type, self.ClassName, self.Name, self.Id)
end

BUILDER
	:GetSet("PlayerOwner", NULL)
	:GetSet("Owner", NULL)

BUILDER
	:StartStorableVars()
		:SetPropertyGroup("appearance")
			:GetSet("Translucent", false)
			:GetSet("IgnoreZ", false)
			:GetSet("NoTextureFiltering", false)
			:GetSet("BlendMode", "", {enums = {
				none = "one;zero;one;zero",
				alpha = "src_alpha;one_minus_src_alpha;one;one_minus_src_alpha",
				multiplicative = "dst_color;zero;dst_color;zero",
				premultiplied = "one;one_src_minus_alpha;one;one_src_minus_alpha",
				additive = "src_alpha;one;src_alpha;one",
			}})
			:GetSet("DrawOrder", 0)
	:EndStorableVars()

PART.AllowSetupPositionFrameSkip = true

local blend_modes = {
	zero = 0,
	one = 1,
	dst_color = 2,
	one_minus_dst_color = 3,
	src_alpha = 4,
	one_minus_src_alpha = 5,
	dst_alpha = 6,
	one_minus_dst_alpha = 7,
	src_alpha_saturate = 8,
	src_color = 9,
	one_minus_src_color = 10,
}

function PART:SetBlendMode(str)
	str = str:lower():gsub("%s+", ""):gsub(",", ";"):gsub("blend_", "")

	self.BlendMode = str

	local tbl = str:Split(";")
	local src_color
	local dst_color

	local src_alpha
	local dst_alpha

	if tbl[1] then src_color = blend_modes[tbl[1]] end
	if tbl[2] then dst_color = blend_modes[tbl[2]] end

	if tbl[3] then src_alpha = blend_modes[tbl[3]] end
	if tbl[4] then dst_alpha = blend_modes[tbl[4]] end

	if src_color and dst_color then
		self.blend_override = {src_color, dst_color, src_alpha, dst_alpha, tbl[5]}
	else
		self.blend_override = nil
	end
end

do -- modifiers
	PART.HandleModifiersManually = false

	function PART:AddModifier(part)
		self:RemoveModifier(part)
		table.insert(self.modifiers, part)
	end

	function PART:RemoveModifier(part)
		for i, v in ipairs(self.modifiers) do
			if v == part then
				table.remove(self.modifiers, i)
				break
			end
		end
	end

	function PART:ModifiersPreEvent(event)
		if #self.modifiers > 0 then
			for _, part in ipairs(self.modifiers) do
				if not part:IsHidden() and not part:GetEventHide() then

					if not part.pre_draw_events then part.pre_draw_events = {} end
					if not part.pre_draw_events[event] then part.pre_draw_events[event] = "Pre" .. event end

					if part[part.pre_draw_events[event]] then
						part[part.pre_draw_events[event]](part)
					end
				end
			end
		end
	end

	function PART:ModifiersPostEvent(event)
		if #self.modifiers > 0 then
			for _, part in ipairs(self.modifiers) do
				if not part:IsHidden() and not part:GetEventHide() then

					if not part.post_draw_events then part.post_draw_events = {} end
					if not part.post_draw_events[event] then part.post_draw_events[event] = "Post" .. event end

					if part[part.post_draw_events[event]] then
						part[part.post_draw_events[event]](part)
					end
				end
			end
		end
	end

end

do
	pac.haloex = include("pac3/libraries/haloex.lua")

	function PART:Highlight(skip_children, data)
		local tbl = {self.Entity and self.Entity:IsValid() and self.Entity or nil}

		if not skip_children then
			for _, part in ipairs(self:GetChildren()) do
				local ent = part.Entity

				if ent and ent:IsValid() then
					table.insert(tbl, ent)
				end
			end
		end

		if #tbl > 0 then
			if data then
				pac.haloex.Add(tbl, unpack(data))
			else
				local pulse = math.abs(1 + math.sin(pac.RealTime * 20) * 255)
				pulse = pulse + 2
				pac.haloex.Add(tbl, Color(pulse, pulse, pulse, 255), 1, 1, 1, true, true, 5, 1, 1)
			end
		end
	end
end

do -- drawing. this code is running every frame
	function PART:DrawChildren(event, pos, ang, draw_type, drawAll)
		if drawAll then
			for i, child in ipairs(self:GetChildrenList()) do
				child:Draw(pos, ang, draw_type, true)
			end
		else
			for i, child in ipairs(self:GetChildren()) do
				child:Draw(pos, ang, draw_type)
			end
		end
	end

	--function PART:Draw(pos, ang, draw_type, isNonRoot)
	function PART:Draw(pos, ang, draw_type)
		if not self.OnDraw then return end

		if self:IsHidden() or self:GetEventHide() then return end

		if
			(
				draw_type == "viewmodel" or draw_type == "hands" or
				((self.Translucent == true or self.force_translucent == true) and draw_type == "translucent")  or
				((self.Translucent == false or self.force_translucent == false) and draw_type == "opaque")
			)
		then
			pos, ang = self:GetDrawPosition()

			self.cached_pos = pos
			self.cached_ang = ang

			if not self.PositionOffset:IsZero() or not self.AngleOffset:IsZero() then
				pos, ang = LocalToWorld(self.PositionOffset, self.AngleOffset, pos, ang)
			end

			if not self.HandleModifiersManually then
				self:ModifiersPreEvent('OnDraw', draw_type)
			end

			if self.IgnoreZ then cam.IgnoreZ(true) end

			if self.blend_override then
				render.OverrideBlendFunc(true,
					self.blend_override[1],
					self.blend_override[2],
					self.blend_override[3],
					self.blend_override[4]
				)

				if self.blend_override[5] then
					render.OverrideAlphaWriteEnable(true, self.blend_override[5] == "write_alpha")
				end

				if self.blend_override[6] then
					render.OverrideColorWriteEnable(true, self.blend_override[6] == "write_color")
				end
			end

			if self.NoTextureFiltering then
				render.PushFilterMin(TEXFILTER.POINT)
				render.PushFilterMag(TEXFILTER.POINT)
			end

			self:OnDraw(self:GetOwner(), pos, ang)

			if self.NoTextureFiltering then
				render.PopFilterMin()
				render.PopFilterMag()
			end

			if self.blend_override then
				render.OverrideBlendFunc(false)

				if self.blend_override[5] then
					render.OverrideAlphaWriteEnable(false)
				end

				if self.blend_override[6] then
					render.OverrideColorWriteEnable(false)
				end
			end

			if self.IgnoreZ then cam.IgnoreZ(false) end

			if not self.HandleModifiersManually then
				self:ModifiersPostEvent('OnDraw', draw_type)
			end
		end
	end
end

function PART:SetDrawOrder(num)
	self.DrawOrder = num
	if self:HasParent() then self:GetParent():SortChildren() end
end

BUILDER:Register()
