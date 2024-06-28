AddCSLuaFile()
local imagecache = {}

local classname = "image_sticker"
local renderItems = {}

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Category        = "Fun + Games"
ENT.PrintName       = "Image Sticker"
ENT.Author          = "March"
ENT.Purpose         = "Projects images in 3D space, attached to a physical entity"

ENT.Editable        = false
ENT.Spawnable       = true
ENT.AdminOnly       = false

function ENT:SpawnFunction(ply, tr, classname)
    if not tr.Hit then return end

    local SpawnPos = tr.HitPos + tr.HitNormal * 16

    local ent = ents.Create(classname)
    ent:SetPos(SpawnPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    ent:Spawn()
    ent:Activate()
    return ent
end

function ENT:InitializeProperties()
    self.__nvorder = 1
    self.__catorder = 1
    self.__nvindexes = {}
    self.__propertiesandtriggers = {}
end

function ENT:RegisterCategory(Category)
    self.__propcategories[ImageStickers.Language.GetPhrase(Category)] = self.__catorder
    self.__catorder = self.__catorder + 1
end

function ENT:AddProperty(Type, Name, Keyname, Title, Category, AdditionalKeys, Default)
    local use_phrases = true
    local order = self.__nvorder

    Keyname = Keyname == nil and string.lower(Name) or Keyname

    local networking_order = self.__nvindexes[Type]
    if networking_order == nil then
        self.__nvindexes[Type] = 0
        networking_order = 0
    end

    local tbl = {}
    tbl.PropertyType = "Property"
    tbl.KeyName = Keyname
    tbl.ValueDefault = Default
    tbl.PropName = Name
    tbl.Edit = {}
    tbl.Edit.type = Type
    tbl.Edit.order = order
    tbl.Edit.title = use_phrases and ImageStickers.Language.GetPhrase(Title) or Title
    tbl.Edit.category = use_phrases and ImageStickers.Language.GetPhrase(Category) or Category

    if AdditionalKeys ~= nil then
        for k, v in pairs(AdditionalKeys) do
            tbl.Edit[k] = v
        end
    end

    if Type == "String" then
        tbl.Edit.type = "Generic"
        tbl.Edit.waitforenter = true
    end

    self:NetworkVar(Type, networking_order, Name, tbl)
    self.__nvorder = self.__nvorder + 1
    self.__nvindexes[Type] = self.__nvindexes[Type] + 1

    self.__propertiesandtriggers[Keyname] = tbl
end

if SERVER then
    util.AddNetworkString("march.imagestickers.enttriggers")
    util.AddNetworkString("march.imagestickers.shrinkwrapmesh")
    net.Receive("march.imagestickers.enttriggers", function(len, ply)
        local ent = net.ReadEntity()
        if not IsValid(ent) then return end

        local trigger = net.ReadString()
        if ent.__propertiesandtriggers[trigger] == nil or ent.__propertiesandtriggers[trigger].PropertyType ~= "Trigger" then
            return print("enttrigger failure: no such trigger named '" .. trigger .. "'")
        end

        local CanEdit = hook.Run("CanEditVariable", ent, ply, key, "N/A", ent.__propertiesandtriggers[trigger])
        if not CanEdit then return end

        local shf, svf = ent.__propertiesandtriggers[trigger].DoShared, ent.__propertiesandtriggers[trigger].DoServerside
        if shf then shf(ent) end
        if svf then svf(ent) end
    end)

    duplicator.RegisterEntityModifier("march.imagestickers.shrinkwrap_pointfile", function(ply, ent, data)
        ImageStickers.Shrinkwrap.UpdateShrinkwrap(ent, data[1])
    end)
end

net.Receive("march.imagestickers.ask_shrinkwrap", function(len, ply)
    if SERVER then
        local ent = net.ReadEntity()
        if ent.pointfile == nil then return end

        net.Start("march.imagestickers.ask_shrinkwrap")
        net.WriteUInt(#ent.pointfile, 16)
        net.WriteData(ent.pointfile, #ent.pointfile)
        return net.Send(ply)
    end

    local datalen = net.ReadUInt(16)
    local pointfile = net.ReadData(datalen)

    local points = ImageStickers.Shrinkwrap.ReadPoints(pointfile)
    ImageStickers.Shrinkwrap.RecalculateMesh(ent, points)
end)

net.Receive("march.imagestickers.shrinkwrapmesh", function(len, ply)
    if CLIENT then
        local ent = net.ReadEntity()
        if not IsValid(ent) then return end

        local datalen = net.ReadUInt(16)
        local pointfile = net.ReadData(datalen)

        local points = ImageStickers.Shrinkwrap.ReadPoints(pointfile)
        ImageStickers.Shrinkwrap.RecalculateMesh(ent, points)
    end

    if SERVER then
        local ent = net.ReadEntity()
        if not IsValid(ent) then return end

        local CanEdit = hook.Run("CanEditVariable", ent, ply, "swrprecalc", "N/A", ent.__propertiesandtriggers["swrprecalc"])
        if not CanEdit then return end

        local datalen = net.ReadUInt(16)
        local pointfile = net.ReadData(datalen)
        if not ImageStickers.Shrinkwrap.IsValidPointfile(pointfile) then
            return ImageStickers.Log("User " .. ply:Nick() .. " [" .. ply:SteamID() .. "] attempted to upload a malformed shrinkwrap point file")
        end

        ImageStickers.Shrinkwrap.UpdateShrinkwrap(ent, pointfile)
        ent.pointfile = pointfile
        duplicator.StoreEntityModifier(ent, "march.imagestickers.shrinkwrap_pointfile", {pointfile})
    end
end)

if SERVER then
    hook.Add("march.imagestickers.newplayer", "imagestickers.update", function(ply, stickers)
        local uid = "imagestickers.update_players." .. string.Replace(tostring(SysTime()), ".", "_")
        local i = 1
        if #stickers > 0 then
            timer.Create(uid, 0.15, #stickers, function()
                local ent = stickers[i]
                if ent.pointfile ~= nil then
                    ImageStickers.Shrinkwrap.UpdateShrinkwrap(ent, ent.pointfile, ply)
                end
                i = i + 1
            end)
        end
    end)
end

function ENT:AddTrigger(Text, Keyname, Category, DoClientside, DoServerside, DoShared)
    Text = ImageStickers.Language.GetPhrase(Text)
    Category = ImageStickers.Language.GetPhrase(Category)
    local order = self.__nvorder

    local tbl = {}
    tbl.PropertyType = "Trigger"
    tbl.KeyName = Name

    tbl.Edit = {}
    tbl.Edit.title = Text
    tbl.Edit.category = Category
    tbl.Edit.order = order

    tbl.DoClientside = DoClientside
    tbl.DoServerside = DoServerside
    tbl.DoShared     = DoShared

    self.__propertiesandtriggers[Keyname] = tbl

    self.__nvorder = self.__nvorder + 1
end

function ENT:SetupDataTables()
    self:InitializeProperties()

    self:AddProperty("String",  "ImageURL",        nil, "imagesticker.ui.imageurl",    "imagesticker.ui.category_imagesettings")
    self:AddProperty("Float",   "ImageAngle",      nil, "imagesticker.ui.imageangle",  "imagesticker.ui.category_imagesettings", {min=0,    max=360}, 0)
    self:AddProperty("Float",   "ImageScale",      nil, "imagesticker.ui.imagescale",  "imagesticker.ui.category_imagesettings", {min=0.01, max=32}, 1)
    self:AddProperty("Float",   "ImageScaleX",     nil, "imagesticker.ui.imagescalex", "imagesticker.ui.category_imagesettings", {min=0.01, max=32}, 1)
    self:AddProperty("Float",   "ImageScaleY",     nil, "imagesticker.ui.imagescaley", "imagesticker.ui.category_imagesettings", {min=0.01, max=32}, 1)

    self:AddProperty("Bool",    "ShouldImageGlow",      "imageglow",   "imagesticker.ui.glowinthedark",   "imagesticker.ui.category_lookandfeel")
    self:AddProperty("Bool",    "ShouldImageTestAlpha", "testalpha",   "imagesticker.ui.enablealphatest", "imagesticker.ui.category_lookandfeel")
    self:AddProperty("Bool",    "Translucency",         "translucent", "imagesticker.ui.maketranslucent", "imagesticker.ui.category_lookandfeel")
    self:AddProperty("Bool",    "Additive",             "additive",    "imagesticker.ui.additiverender",  "imagesticker.ui.category_lookandfeel")
    self:AddProperty("Bool",    "Nocull",               "nocull",      "imagesticker.ui.renderbackside",  "imagesticker.ui.category_lookandfeel")

    self:AddProperty("Bool",    "Shrinkwrap",         nil, "imagesticker.ui.enableshrinkwrap",    "imagesticker.ui.category_shrinkwrap")
    self:AddProperty("Bool",    "ShrinkwrapAccuracy", nil, "imagesticker.ui.shrinkwrapaccuracy",  "imagesticker.ui.category_shrinkwrap", nil, true)
    self:AddProperty("Int",     "ShrinkwrapXRes",     nil, "imagesticker.ui.shrinkwrap_xpoints",  "imagesticker.ui.category_shrinkwrap", {min = 2, max = 10}, 5)
    self:AddProperty("Int",     "ShrinkwrapYRes",     nil, "imagesticker.ui.shrinkwrap_ypoints",  "imagesticker.ui.category_shrinkwrap", {min = 2, max = 10}, 5)
    self:AddProperty("Float",   "ShrinkwrapOffset",   nil, "imagesticker.ui.shrinkwrap_offset",   "imagesticker.ui.category_shrinkwrap", {min = 0, max = 200}, 0.5)
    self:AddProperty("Bool",   "ShrinkwrapCullMisses",   nil, "imagesticker.ui.shrinkwrap_throwawaynonhits",   "imagesticker.ui.category_shrinkwrap", nil, true)

    self:AddTrigger("imagesticker.ui.recalculate_shrinkwrap", "swrprecalc", "imagesticker.ui.category_shrinkwrap", function(self)
        local points = ImageStickers.Shrinkwrap.RecalculatePoints(self, self:GetShrinkwrapXRes(), self:GetShrinkwrapYRes(), self:GetShrinkwrapOffset(), self:GetShrinkwrapAccuracy() and 2 or 1, self:GetShrinkwrapCullMisses())
        local pointstring = ImageStickers.Shrinkwrap.WritePoints(points)
        ImageStickers.Shrinkwrap.UpdateShrinkwrap(self, pointstring)
    end)

    self:AddProperty("Bool",    "DrawShrinkwrapGizmo",       nil, "imagesticker.ui.drawshrinkwrapgizmo",    "imagesticker.ui.category_shrinkwrap", nil, true)
 end

 function ENT:Initialize()
    self:DrawShadow(false)
    if CLIENT then
        local uid = "imagestickers.wait4owner" .. string.Replace(SysTime(), ".", "_")
        ImageStickers.AskOwner(self)
        timer.Create(uid, 0.5, 0, function()
            --print("Wtf! ", tostring(self.StickerOwner))
            if self.StickerOwner ~= "" and self.StickerOwner ~= nil then
                timer.Remove(uid)
                return
            end

            ImageStickers.AskOwner(self)
        end)
    end
    self.__propcategories = {}
    self:RegisterCategory("imagesticker.ui.category_imagesettings")
    self:RegisterCategory("imagesticker.ui.category_lookandfeel")
    self:RegisterCategory("imagesticker.ui.category_shrinkwrap")

    if SERVER then
        self:SetModel("models/hunter/plates/plate05x05.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if phys:IsValid() then phys:Wake() end
    end
    self:NetworkVarNotify("ImageURL", self.OnImageURLChange)
    if CLIENT then
        self.LastUpdateCheck = CurTime()
        self.ShrinkwrapMesh = Mesh()
        self.Updates = {
            {
                check = function(x) return x:GetColor() end, change = function(self, ent)
                    local c = self.value

                    ent.image.material:SetVector("$color", Vector(c.r / 255, c.g / 255, c.b / 255))
                    ent.image.material:SetFloat("$alpha", c.a / 255)
                end
            },
            {   check = function(x) return x:GetAdditive() end, change = function(self, ent)
                    ent.image.material:SetInt("$flags", ImageStickers.GetFlags(ent))
                end
            },
            {   check = function(x) return x:GetShouldImageTestAlpha() end, change = function(self, ent)
                    ent.image.material:SetInt("$flags", ImageStickers.GetFlags(ent))
                end
            },
            {   check = function(x) return x:GetTranslucency() end, change = function(self, ent)
                    ent.image.material:SetInt("$flags", ImageStickers.GetFlags(ent))
                end
            },
            {   check = function(x) return x:GetNocull() end, change = function(self, ent)
                    ent.image.material:SetInt("$flags", ImageStickers.GetFlags(ent))
                end
            }
        }

        local scale = Vector(1,1,0.1)

        local mat = Matrix()
        mat:Scale(scale)
        self:EnableMatrix("RenderMultiply", mat)
        self:CheckIfURLCached()
    end

    if self:GetImageURL() ~= "" then
        self:OnImageURLChange("ImageURL", "", self:GetImageURL())
    else -- self:SetImageAngle(0) self:SetImageScale(1) self:SetImageScaleX(1) self:SetImageScaleY(1) self:SetShouldImageGlow(false)
        for k, v in pairs(self.__propertiesandtriggers) do
            if v.ValueDefault ~= nil then
                self["Set" .. v.PropName](self, v.ValueDefault)
            end
        end
    end

end

--Trick to make Wiremod think this is a GPU renderscreen.
--Only really made for EGP:egpMaterialFromScreen()

function ENT:ForceGPU()
    if not self.image or self.image.errored or self.image.loading then return end
    self.GPU = {RT = self.image.material:GetTexture("$basetexture")}
end

if CLIENT then
    function ENT:Invalidate()
        if not self.image then return end

        for _, v in ipairs(self.Updates) do
            v.value = v.check(self)
            if self.image:readytodraw() then
                v:change(self)
            end
        end
    end
end

function ENT:OnImageURLChange(name, old, new)
    if CLIENT then
        self:ProcessImageURL(new)
    end

    if SERVER and old ~= new then
        ImageStickers.Logging.LogImageURLChange(self, new)
    end
end

function ENT:CheckIfURLCached()
    if not IsValid(self) then return end

    if not self.image then
        local url = self:GetImageURL()
        if imagecache[url] == nil then
            self:ProcessImageURL(url)
        end
    end
    timer.Simple(1, function() if not IsValid(self) then return end self.CheckIfURLCached(self) end)
end

function ENT:NewImageStruct(errored, loading)
    local ret = {
        errored = errored or false,
        loading = loading,

        readytodraw = function(self)
            return self.errored == false and self.loading == false
        end,
        setError = function(self, reason)
            self.errored = true
            self.error = reason
        end
    }
    return ret
end

function ENT:CreateImage(materialData, animated, link)
    self.image = self:NewImageStruct(false, true)
    self.image.animated = animated
    self.image.link = link
    self.image.width = materialData.width
    self.image.height = materialData.height

    mat = CreateMaterial("imageloader_" .. util.CRC(link), "VertexLitGeneric", {
        ["$alpha"] = 1,
        ["$basetexture"] = materialData.raw:GetString("$basetexture"),
        ["$model"] = 1,
        ["$translucent"] = 1,
        ["$nocull"] = 0,
        ["$vertexalpha"] = 1,
        ["$vertexcolor"] = 1,
        ["$vertexalphatest"] = 1,
      }
    )
    mat:SetInt("$flags", 0)

    ImageStickers.Debug(mat:GetString("$basetexture"))
    mat:Recompute()
    self.image.material = mat

    self.image.loading = false
    self:Invalidate()
    self:ForceGPU()
end

function ENT:_ProcessImageURL(url)
    if SERVER then return end

    self.image = self:NewImageStruct(false, true)

    if imagecache[url] == nil then
        http.Fetch(url,
            function(body, size, headers, code)
                if code == 404 then
                    self.image = self:NewImageStruct()
                    self.image:setError("Not found [404]") -- TODO: use localization?
                    return
                end

                if #body < 4 then
                    self.image:setError(string.format("Bad body length (%d)", #body)) -- TODO: use localization?
                    return
                end

                local header = string.sub(body, 1, 4)
                local animated = false
                local fileExtension

                -- https://en.wikipedia.org/wiki/List_of_file_signatures
                if header == "\x89\x50\x4E\x47" --[[ PNG ]] then
                    fileExtension = "png"
                elseif
                    --[[ JPEG, JPG ]]
                    header == "\xFF\xD8\xFF\xDB" or
                    header == "\xFF\xD8\xFF\xE0" or
                    header == "\xFF\xD8\xFF\xEE" or
                    header == "\xFF\xD8\xFF\xE1"
                then
                    fileExtension = "jpg"
                elseif header == "\x47\x49\x46\x38" --[[ GIF ]] then
                    fileExtension = "dat" -- gmod doesn't allow to save .gif files, so use .dat instead
                    animated = true
                else
                    local h1, h2, h3, h4 = string.byte(header, 1, 4)

                    self.image = self:NewImageStruct()
                    self.image:setError(string.format("Unknown file (%x %x %x %x)", h1, h2, h3, h4)) -- TODO: use localization?
                    return
                end

                file.CreateDir("temp/imagesticker/")
                local saved_data = "temp/imagesticker/" .. util.CRC(url) .. "." .. fileExtension
                file.Write(saved_data, body)

                if not animated then
                    --Load file as material
                    local rawMaterial = Material("../data/" .. saved_data, "nocull")
                    local materialData = {}

                    materialData.raw = rawMaterial
                    materialData.animated = animated
                    materialData.width = rawMaterial:GetInt("$realwidth")
                    materialData.height = rawMaterial:GetInt("$realheight")
                    imagecache[url] = materialData
                    self:CreateImage(materialData, animated, url)
                else
                    self.image = self:NewImageStruct()
                    self.image:setError(ImageStickers.Language.GetPhrase("imagesticker.gifnotsuppported", "GIF files are currently not supported."))
                end
            end,
            function(err)
                self.image = self:NewImageStruct()
                self.image:setError("Bad HTTP: " .. err)
            end,
        {})
    else
        local materialData = imagecache[url]
        self:CreateImage(materialData, materialData.animated, url)
    end

    self:ForceGPU()
end

function ENT:ProcessImageURL(new)
    if SERVER then return end

    self.image = self:NewImageStruct(false, true)

    local link

    if ImageStickers.ConVars.sv_imagestickers_allow_any_url:GetBool() then
        link = new
    else
        local isImgur, imgurID

        local final_link = string.Replace(new, ".jpeg", ".jpg")
        isImgur, imgurID, link = ImageStickers.IsImgurLink(final_link)

        if not imgurID or not isImgur then
            self.image = self:NewImageStruct()
            self.image:setError(link)

            return
        end
    end

    self:_ProcessImageURL(link)
end

function ENT:Draw()
    --local stopwatchStart = SysTime()
    self:DrawModel()

    ImageStickers.RenderImageOntoSticker(self)

    --allows flashlights to work on the images
    if not self:GetShouldImageGlow() then
        render.RenderFlashlights(function() ImageStickers.RenderImageOntoSticker(self) end)
    end
    --print("Time taken to render entity:", (SysTime() - stopwatchStart) * 1000,"ms")
end

function ENT:GetBorderRect3D()
    return ImageStickers.GetBorderRect3D(self)
end

function ENT:Think()
    if SERVER then return end

    local now = CurTime()
    if now - (self.LastUpdateCheck or 0) < 0.1 then return end

    local imageStatus = false
    if self.image ~= nil and self.image:readytodraw() then
        imageStatus = true
        for _, v in ipairs(self.Updates) do
            local last = v.value
            v.value = v.check(self)
            if last ~= v.value then
                v:change(self)
            end
        end
    else
        imageStatus = false
    end

    if self.LastUpdateImageStatus ~= imageStatus then
        local m = Matrix()
        if imageStatus then
            m:Scale(Vector(0, 0, 0))
        else
            m:Scale(Vector(1, 1, 0.1))
        end
        self:EnableMatrix("RenderMultiply", m)
    end

    self.LastUpdateImageStatus = imageStatus
    self.LastUpdateCheck = now
end