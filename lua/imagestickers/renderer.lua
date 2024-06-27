local ImageStickers = ImageStickers

local render_SetMaterial = render.SetMaterial
local surface_DrawRect = surface.DrawRect
local surface_SetDrawColor = surface.SetDrawColor
local surface_SetFont = surface.SetFont
local surface_GetTextSize= surface.GetTextSize
local draw_SimpleText = draw.SimpleText
local surface_DrawOutlinedRect = surface.DrawOutlinedRect
local Vector = Vector
local render_DrawLine = render.DrawLine
local Angle = Angle

local render_DrawQuadEasy = render.DrawQuadEasy
local cam_PushModelMatrix = cam.PushModelMatrix
local cam_PopModelMatrix = cam.PopModelMatrix
local cam_Start3D2D = cam.Start3D2D

local renderDebuggingInformation = false
local renderIndex = 0

local hoveredEnt

local badParents = {
    ["ContextMenu"] = true,
    ["GModBase"] = true,
}

local pi = math.pi

function ImageStickers.AnimationSmoother(f, z, r, x)
    local self = {}

    self.k1 = z / (pi * f)
    self.k2 = 1 / ((2 * pi * f) * (2 * pi * f))
    self.k3 = r * z / (2 * pi * f)
    self.tcrit = 0.8 * (math.sqrt(4 * self.k2  + self.k1 * self.k1) - self.k1)

    self.xp = x
    self.y = x
    self.yd = 0

    self.lastupdate = CurTime()
    local tolerance = 0.01
    function self:update(x, xd)
        if self.y - tolerance <= x and x <= self.y + tolerance then return x end

        local t = CurTime() - self.lastupdate
        if t == 0 then return x end

        if xd == nil then
            xd = (x - self.xp)
            self.xp = x
        end

        local iterations = math.ceil(t / self.tcrit)
        t = t / iterations

        for i = 0, iterations do
            self.y = self.y + t * self.yd
            self.yd = self.yd + t * (x + self.k3 * xd - self.y - self.k1 * self.yd) / self.k2
        end

        self.lastupdate = CurTime()

        return self.y
    end

    return self
end

hook.Add("RenderScene", "march.imagestickers.reset_render_order", function()
    renderIndex = 0

    local p = vgui.GetHoveredPanel()
    if IsValid(p) then
        for i = 1, 3000 do
            local tp = p:GetParent()
            if not IsValid(tp) or badParents[tp:GetName()] == true then break end
            p = tp
        end
        --determine hovered entity
        if p.IsImageStickerDialog == true then
            hoveredEnt = p.Properties.m_Entity
        else
            hoveredEnt = nil
        end
    else
        hoveredEnt = nil
    end
end)

local curtime = CurTime
function ImageStickers.UpdateAnimatedBorder(self, on)
    if self.animateOn == false and on then
        self.animateCurtimeStart = curtime()
    end
    self.animateOn = on
end

function ImageStickers.RenderAnimatedBorder(self, w, h)
    if not self.animateOn then return end

    local now = curtime()
    local animationTime = now - self.animateCurtimeStart

    local offset = animationTime % 1
    local offsetV = math.ease.OutElastic(offset) * 32
    local alphaA = math.ease.OutQuad(offset) * 255
    surface.SetDrawColor(Color(200, 235, 255, 255 - alphaA))

    surface.DrawLine(-w - offsetV, -h - offsetV, w + offsetV, -h - offsetV) --top line
    surface.DrawLine(-w - offsetV, h + offsetV, w + offsetV, h + offsetV) --bottom line

    surface.DrawLine(-w - offsetV, h + offsetV, -w - offsetV, -h - offsetV) --left line
    surface.DrawLine(w + offsetV, h + offsetV, w + offsetV, -h - offsetV) --right line
end

--https://developer.valvesoftware.com/wiki/Material_Flags
function ImageStickers.GetFlags(self)
    local additive = self:GetAdditive() == true and 128 or 0
    local enableAlphaTest = self:GetShouldImageTestAlpha() == true and 256 or 0
    local translucent = self:GetTranslucency() == true and 2097152 or 0
    local nocull = self:GetNocull() == true and 8192 or 0

    return additive + enableAlphaTest + translucent + nocull + 16 -- 16 = vertex color
end

local math_Clamp = math.Clamp
local render_SuppressEngineLighting = render.SuppressEngineLighting
local Matrix = Matrix

function ImageStickers.GetBorderRect3D(self)
    local image = self.image

    local w, h = 0, 0

    if image ~= nil and image.errored == false and image.material ~= nil then
        local imageScale = self:GetImageScale()
        local imageScaleX, imageScaleY = math_Clamp(imageScale * self:GetImageScaleX(), 0, 32), math_Clamp(imageScale * self:GetImageScaleY(), 0, 32)

        local tw, th = image.width / 3, image.height / 3
        tw = tw * 0.08
        th = th * 0.08

        h = math_Clamp(tw * imageScaleX, 0.1, 9000000)
        w = math_Clamp(th * imageScaleY, 0.1, 90000000)
    else
        w = 146 * 0.08
        h = 146 * 0.08
    end

    return {
        TL = self:LocalToWorld(Vector(-w*1,-h*1,1.6)),
        TR = self:LocalToWorld(Vector(-w*1,h*1,1.6)),
        BL = self:LocalToWorld(Vector(w*1,-h*1,1.6)),
        BR = self:LocalToWorld(Vector(w*1,h*1,1.6))
    }
end

local imagePosition, imageNormal = Vector(0, 0, -1.45), Vector(0,0,1)
local nolighting = CreateMaterial("march_imagestickers_unlittex", "UnlitGeneric", {
    ["$basetexture"] = "models/debug/debugwhite",
    ["$selfillum"] = 1,
    ["$vertexalpha"] = 1
})

function ImageStickers.RenderImageOntoSticker(self)
    if not self.Smoothing then
        local f, z, r = 4.461, 1.5, 1.91
        self.Smoothing = {
            ScaleX = ImageStickers.AnimationSmoother(f,z,r,1),
            ScaleY = ImageStickers.AnimationSmoother(f,z,r,1),
            Angle = ImageStickers.AnimationSmoother(f,z,r,0)
        }
    end

    --local stopwatchStart = SysTime()

    ImageStickers.UpdateAnimatedBorder(self, hoveredEnt == self)

    local TextResult = ""
    local image = self.image
    local imageScale = self:GetImageScale()
    local image_errored, image_error, image_loading, image_material

    if image ~= nil then
        image_errored = image.errored
        image_error = image.error
        image_loading = image.loading
        image_material = image.material
    end

    local shouldDraw2D = true
    local w, h = 0, 0
    local isRenderingImage = false

    if image == nil then
        TextResult = ImageStickers.Language.GetPhrase("imagesticker.nourl", "No URL")
    else
        if image_errored ~= true and image_loading ~= true then
            shouldDraw2D = false
            TextResult = nil
            if image.width == nil or image.height == nil then
                PrintTable(image)
                error("Image.Width or Image.Height is nil. Please provide the table printed in your console with your error report.")
            end
            w, h = image.width / 3, image.height / 3

            local imageScaleX, imageScaleY = math_Clamp(imageScale * self:GetImageScaleX(), 0, 32), math_Clamp(imageScale * self:GetImageScaleY(), 0, 32)

            w = math_Clamp(w * imageScaleX, 0.1, 9000000)
            h = math_Clamp(h * imageScaleY, 0.1, 90000000)

            self.Smoothing.ScaleX:update(w)
            self.Smoothing.ScaleY:update(h)
            self.Smoothing.Angle:update(self:GetImageAngle())

            if self:GetShouldImageGlow() then render_SuppressEngineLighting(true) end

            render_SetMaterial(image_material)

            local magicnumber = ImageStickers.SizeMagicNumber

            if self:GetShrinkwrap() then -- Shrinkwrap rendering mode
                local renderbounds = Vector(400, 400, 400)
                self:SetRenderBounds(-renderbounds, renderbounds) -- lazy
                local m = Matrix()
                m:Translate(self:GetPos())
                m:Rotate(self:GetAngles())
                m:Scale(Vector(1, 1, 1))

                isRenderingImage = true
                local points
                cam_PushModelMatrix(m)
                    if self:GetDrawShrinkwrapGizmo() and self.StickerOwner == LocalPlayer():SteamID() then
                        render_DrawQuadEasy(imagePosition + Vector(0,0,1), imageNormal, self.Smoothing.ScaleX.y/magicnumber, self.Smoothing.ScaleY.y/magicnumber, Color(255,255,255,255), 180 - self.Smoothing.Angle.y)
                        render_SetMaterial(nolighting)

                        do -- Draw the preview gizmo
                            render.DrawSphere(Vector(0,0,0), 2, 16, 8, Color(255,255,255,125))
                            local s = Vector(self.Smoothing.ScaleY.y/magicnumber/2, self.Smoothing.ScaleX.y/magicnumber/2, 0.5)
                            render.DrawWireframeBox(Vector(0,0,0), Angle(0,0,0), -s, s, Color(255,255,255,80), true)
                            render.DrawBox(Vector(0,0,0), Angle(0,0,0), -Vector(s.x, s.y, 327.68), Vector(s.x, s.y, 0), Color(215,235,255,25))

                            local arrowLength    = 32 -- Length of arrow
                            local arrowSize      = 2  -- How wide the arrow head will be
                            local arrowPokeySize = 8  -- How tall the arrow head will be
                            local arrowRate      = 2  -- How fast the arrow head spins
                            local arrowFidelity  = 4  -- How many points the arrow head has
                            render.DrawLine(Vector(0,0,0), Vector(0,0,-arrowLength), Color(255,255,255,200), true)

                            for i = 0, arrowFidelity - 1 do
                                local coff     = (math.pi / (arrowFidelity / i))       * 2
                                local coffNext = (math.pi / (arrowFidelity / (i + 1))) * 2

                                local s,  c  = math.sin(CurTime() * arrowRate + coff),     math.cos(CurTime() * arrowRate + coff)
                                local sn, cn = math.sin(CurTime() * arrowRate + coffNext), math.cos(CurTime() * arrowRate + coffNext)

                                -- The lines that draw from the arrow tip, to the base of the arrow head
                                render.DrawLine(Vector(s * arrowSize,c * arrowSize,-arrowLength + arrowPokeySize), Vector(0,0,-arrowLength), Color(255,255,255,200), true)
                                -- The lines that draw from the base of the arrow head back into the arrow shaft
                                render.DrawLine(Vector(s * arrowSize,c * arrowSize,-arrowLength + arrowPokeySize), Vector(0,0,-arrowLength+ arrowPokeySize), Color(255,255,255,200), true)
                                -- The lines that attach the arrow head pieces together
                                render.DrawLine(Vector(s * arrowSize,c * arrowSize,-arrowLength + arrowPokeySize), Vector(sn * arrowSize,cn * arrowSize,-arrowLength + arrowPokeySize), Color(255,255,255,200), true)
                            end

                            -- Approximate renderer of the shrinkwrap (using physics mesh only for performance)
                            points = ImageStickers.Shrinkwrap.RecalculatePoints(self, self:GetShrinkwrapXRes(), self:GetShrinkwrapYRes(), self:GetShrinkwrapOffset(), 1, self:GetShrinkwrapCullMisses()).points

                            for y = 1, #points - 1 do
                                local row = points[y]
                                for x = 1, #row - 1 do
                                    local v1, v2, v3, v4 = points[y][x], points[y][x + 1], points[y + 1][x + 1], points[y + 1][x]
                                    if ImageStickers.Shrinkwrap.IsQuadLegitimate(v1, v2, v3, v4) then
                                        render.DrawLine(v1.hitpos, v2.hitpos, Color(255,255,255,200), true)
                                        render.DrawLine(v2.hitpos, v3.hitpos, Color(255,255,255,200), true)
                                        render.DrawLine(v3.hitpos, v4.hitpos, Color(255,255,255,200), true)
                                        render.DrawLine(v4.hitpos, v1.hitpos, Color(255,255,255,200), true)
                                    end
                                end
                            end
                        end
                    end

                    -- Draw the actual shrinkwrap mesh
                    if self.ShrinkwrapMesh ~= nil then
                        render_SetMaterial(image_material)
                        self.ShrinkwrapMesh:Draw()
                    end
                cam_PopModelMatrix()

                -- for normal checks (normals may still be messed up...)
                --[[
                for y = 1, #points - 1 do
                    local row = points[y]
                    for x = 1, #row - 1 do
                        local v1, v2, v3, v4 = points[y][x], points[y][x + 1], points[y + 1][x + 1], points[y + 1][x]
                        if ImageStickers.Shrinkwrap.IsQuadLegitimate(v1, v2, v3, v4) then
                            render.DrawLine(self:LocalToWorld(v1.hitpos), self:LocalToWorld(v1.hitpos) + (v1.normal * 32), Color(200,200,255,200), true)
                        end
                    end
                end]]
            else -- Normal rendering mode
                self:SetRenderBounds(Vector(-w, -h, -1), Vector(w, h, 1))
                local m = Matrix()
                    m:Translate(self:GetPos())
                    m:Rotate(self:GetAngles())
                    m:Scale(Vector(1, 1, 1))

                isRenderingImage = true
                cam_PushModelMatrix(m)
                    render_DrawQuadEasy(imagePosition, imageNormal, self.Smoothing.ScaleX.y/magicnumber, self.Smoothing.ScaleY.y/magicnumber, color_white, 180 - self.Smoothing.Angle.y)
                cam_PopModelMatrix()
            end
            render_SuppressEngineLighting(false)
        end
    end

    local drawRenderAnimatedBorder = hoveredEnt == self

    if drawRenderAnimatedBorder or shouldDraw2D or renderDebuggingInformation then
        local lv, la = self:LocalToWorld(Vector(0, 0,0.5)), self:LocalToWorldAngles(Angle(0,90,00))
        cam_Start3D2D(lv, la, 0.08)
            if image == nil then
                TextResult = ImageStickers.Language.GetPhrase("imagesticker.nourl", "No URL")
            else
                if image_errored ~= true and image_loading ~= true then
                    TextResult = nil

                    if renderDebuggingInformation then
                        render_DrawLine(Vector(w, -h, -2), Vector(w, h, -2))
                        render_DrawLine(Vector(-w, -h, -2), Vector(w, -h, -2))
                        render_DrawLine(Vector(-w, -h, -2), Vector(-w, h, -2))
                        render_DrawLine(Vector(-w, h, -2), Vector(w, h, -2))

                        draw_SimpleText("Image angle: " .. self:GetImageAngle(), "DermaDefault", -image.width/2,image.height/2)
                        draw_SimpleText("Image scale X: " .. self:GetImageScaleX(), "DermaDefault", -image.width/2,(image.height/2) + (16 * 1) )
                        draw_SimpleText("Image scale Y: " .. self:GetImageScaleY(), "DermaDefault", -image.width/2,(image.height/2) + (16 * 2) )
                        draw_SimpleText("Image scale: " .. self:GetImageScale(), "DermaDefault", -image.width/2,(image.height/2) + (16 * 3) )
                        draw_SimpleText("Rendering Order: " ..renderIndex, "DermaLarge", -image.width/2,(image.height/2) + (16 * 4) )
                    end
                end

                if image_loading then
                    TextResult = ImageStickers.Language.GetPhrase("imagesticker.loading", "Loading...")
                end
                if image_errored then
                    TextResult = ImageStickers.Language.GetPhrase("imagesticker.errored", "Errored:") .. " " .. image_error
                end
            end

            if drawRenderAnimatedBorder then
                if not isRenderingImage then
                    w = 146 * 1
                    h = 146 * 1
                end
                ImageStickers.RenderAnimatedBorder(self, w, h)
            end

            local boxSize = 146
            if TextResult ~= nil or image_errored then
                surface_SetFont("DermaDefault")
                local X, Y = surface_GetTextSize(TextResult)
                local padding = 12
                X = X + padding
                Y = Y + padding

                surface_SetDrawColor(0, 0, 0, 125)
                surface_DrawOutlinedRect(-boxSize, -boxSize, boxSize*2, boxSize*2, 8)
                surface_DrawRect(-X / 2, -Y / 2, X, Y)
                draw_SimpleText(TextResult or image_error, "DermaDefault", 0, 0, c ,TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    --print("took " .. ((SysTime() - stopwatchStart) * 1000) .. " ms")
    renderIndex = renderIndex + 1
end